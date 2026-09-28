library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_usb.ukp.all;
use nsl_usb.hid_program.all;
use nsl_simulation.control.all;

entity tb is
end entity;

architecture arch of tb is

  constant lbl_backward_c: label_t := 7;
  constant lbl_forward_c: label_t := 3;

  -- Assembly of this program is checked word by word below.  It uses
  -- every opcode that carries an operand, both branch directions, and
  -- a label placed at the very last instruction.
  constant test_program_c: program_t :=
    lbl(lbl_backward_c)
    & ldi(42)
    & out4(dp => "1010", dm => "0101")
    & save(6, 9)
    & out_bytes(from_hex("deadbeef"))
    & bz(lbl_forward_c)
    & bc(lbl_forward_c)
    & bnak(lbl_backward_c)
    & berr(lbl_backward_c)
    & djnz(lbl_backward_c)
    & call(lbl_forward_c)
    & jmp(lbl_backward_c)
    & start
    & usb_in
    & out0
    & hiz
    & toggle
    & wait_frame
    & ret
    & lbl(lbl_forward_c)
    & nop;

  -- Word encoding is the 5-bit opcode_t'pos in bits 15 downto 11 and
  -- the operand in bits 10 downto 0.  The backward label resolves to
  -- address 0, the forward one to address 21.
  -- Every opcode carrying a label must come out of the assembler with
  -- an address in it instead.  One that does not is assembled with the
  -- label number still there and branches into the middle of the
  -- program, which is a thing that happened once.
  constant branch_program_c: program_t :=
    bfs(lbl_forward_c)
    & bout(lbl_forward_c)
    & bstall(lbl_forward_c)
    & nop
    & lbl(lbl_forward_c)
    & sof(0);
  constant branch_rom_c: rom_t := assemble(branch_program_c);

  type opcode_vector is array (natural range <>) of opcode_t;
  constant branch_opcodes_c: opcode_vector := (UKP_BFS, UKP_BOUT, UKP_BSTALL);

  constant output_program_c: program_t :=
    out_report
    & out_report_acked
    & out_report_dropped
    & out_toggle_reset;
  constant output_rom_c: rom_t := assemble(output_program_c);
  constant output_expected_c: rom_t(0 to 3) := (
    0 => opcode_encode(UKP_OUTR) & "00000000000",
    1 => opcode_encode(UKP_OCTL) & "00000000000",
    2 => opcode_encode(UKP_OCTL) & "00000000001",
    3 => opcode_encode(UKP_OCTL) & "00000000010");

  -- The program hardware was verified with, without output reports:
  -- its length and a hash of its words.  Enabling output reports must
  -- not change it by a single word when they are not asked for.
  constant pinned_config_c: hid_program_config_t := (
    poll_interval_ms => 8, report_length => 7,
    configuration_value => 1, debounce_ms => 200);
  constant pinned_length_c: natural := 270;
  constant pinned_hash_c: natural := 2983036;
  constant pinned_rom_c: rom_t := assemble(hid_program(pinned_config_c));
  constant output_hid_rom_c: rom_t
    := assemble(hid_program(pinned_config_c, output_enabled => true));

  function rom_hash(r: rom_t) return natural
  is
    variable h: natural := 0;
  begin
    for i in r'range loop
      h := (h * 31 + to_integer(unsigned(r(i)))) mod 16777213;
    end loop;
    return h;
  end function;

  function is_output_op(w: word_t) return boolean
  is
  begin
    return w(15 downto 11) = opcode_encode(UKP_OUTR)
      or w(15 downto 11) = opcode_encode(UKP_BOUT)
      or w(15 downto 11) = opcode_encode(UKP_BSTALL)
      or w(15 downto 11) = opcode_encode(UKP_OCTL);
  end function;

  function is_branch_op(w: word_t) return boolean
  is
    constant ops_c: opcode_vector := (
      UKP_BZ, UKP_BC, UKP_BNAK, UKP_BERR, UKP_BFS, UKP_BMORE,
      UKP_BOUT, UKP_BSTALL, UKP_DJNZ, UKP_JMP, UKP_CALL);
  begin
    for i in ops_c'range loop
      if w(15 downto 11) = opcode_encode(ops_c(i)) then
        return true;
      end if;
    end loop;
    return false;
  end function;

  constant expected_c: rom_t(0 to 21) := (
    0 => x"082a",
    1 => x"18a5",
    2 => x"7189",
    3 => x"30de",
    4 => x"30ad",
    5 => x"30be",
    6 => x"30ef",
    7 => x"4015",
    8 => x"4815",
    9 => x"5000",
    10 => x"5800",
    11 => x"6000",
    12 => x"9015",
    13 => x"8800",
    14 => x"1000",
    15 => x"7800",
    16 => x"2000",
    17 => x"2800",
    18 => x"6800",
    19 => x"8000",
    20 => x"3800",
    21 => x"0000");

  constant test_rom_c: rom_t := assemble(test_program_c);

  constant hid_rom_c: rom_t := assemble(hid_program(hid_program_defaults_c));

  function word_image(w: word_t) return string
  is
  begin
    return integer'image(to_integer(unsigned(w)));
  end function;

begin

  check: process
  begin
    for i in branch_opcodes_c'range loop
      assert branch_rom_c(i)(15 downto 11) = opcode_encode(branch_opcodes_c(i))
        report opcode_t'image(branch_opcodes_c(i))
        & " did not assemble to its own opcode"
        severity failure;

      assert unsigned(branch_rom_c(i)(10 downto 0)) = 4
        report opcode_t'image(branch_opcodes_c(i))
        & " kept its label number instead of the address it stands for: "
        & "operand is "
        & integer'image(to_integer(unsigned(branch_rom_c(i)(10 downto 0))))
        severity failure;
    end loop;

    for i in output_expected_c'range loop
      assert output_rom_c(i) = output_expected_c(i)
        report "Output word " & integer'image(i) & " is "
        & word_image(output_rom_c(i)) & ", expected "
        & word_image(output_expected_c(i))
        severity failure;
    end loop;

    assert pinned_rom_c'length = pinned_length_c
      and rom_hash(pinned_rom_c) = pinned_hash_c
      report "HID host program without output reports changed: "
      & integer'image(pinned_rom_c'length) & " words hashing to "
      & integer'image(rom_hash(pinned_rom_c))
      severity failure;

    for i in pinned_rom_c'range loop
      assert not is_output_op(pinned_rom_c(i))
        report "Output instruction at " & integer'image(i)
        & " of a program without output reports"
        severity failure;
    end loop;

    assert output_hid_rom_c'length > pinned_rom_c'length
      report "Enabling output reports did not add anything"
      severity failure;

    for i in output_hid_rom_c'range loop
      if is_branch_op(output_hid_rom_c(i)) then
        assert to_integer(unsigned(output_hid_rom_c(i)(10 downto 0)))
          < output_hid_rom_c'length
          report "Branch at " & integer'image(i)
          & " of the output-enabled program leaves the program"
          severity failure;
      end if;
    end loop;

    report "HID host program with output reports is "
      & integer'image(output_hid_rom_c'length) & " instructions"
      severity note;

    assert instruction_count(test_program_c) = expected_c'length
      report "Test program has "
      & integer'image(instruction_count(test_program_c))
      & " instructions, expected " & integer'image(expected_c'length)
      severity failure;

    assert test_rom_c'length = expected_c'length
      report "Assembled ROM has " & integer'image(test_rom_c'length)
      & " words, expected " & integer'image(expected_c'length)
      severity failure;

    for i in expected_c'range loop
      assert test_rom_c(i) = expected_c(i)
        report "Word " & integer'image(i) & " is " & word_image(test_rom_c(i))
        & ", expected " & word_image(expected_c(i))
        severity failure;
    end loop;

    report "HID host program is " & integer'image(hid_rom_c'length)
      & " instructions"
      severity note;

    assert hid_rom_c'length > 80
      report "HID host program is implausibly short: "
      & integer'image(hid_rom_c'length) & " instructions"
      severity failure;

    terminate(0);
    wait;
  end process;

end architecture;
