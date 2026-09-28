library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_simulation, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_usb.io.all;
use nsl_usb.usb.all;
use nsl_usb.ls_bfm.all;
use nsl_usb.hid_host.all;
use nsl_usb.hid_program.all;
use nsl_simulation.logging.all;

-- Output reports to an interrupt OUT endpoint, at either speed.
--
-- The full-speed case is built as in host_fs: lines crossed between
-- host and device model, host clocked at an eighth of what it is told
-- so that its full-speed bit lasts one low-speed bit of the model.
--
-- The device model lets every report's first attempt go unanswered
-- and NAKs the next two, fails the simulation on a bad CRC16, an
-- oversized packet or an unexpected data toggle, and reports what it
-- accepted.  This bench checks what went through, in order and once
-- each, and the drop paths: too long for the buffer, STALLed, and
-- pending when the device goes away, the latter followed by a
-- re-enumeration after which the toggle must be back to DATA0.
entity output_test is
  generic(
    full_speed_c: boolean
    );
  port(
    done_o: out std_ulogic
    );
end entity;

architecture beh of output_test is

  constant device_descriptor_c: byte_string
    := from_hex("12010001000000080015c10e000100000001");

  -- One HID interface, interrupt IN and OUT endpoints 1.
  constant config_descriptor_c: byte_string := from_hex(
    "090229000101008032"
    & "090400000203000000"
    & "092111010001223f00"
    & "0705810310000a"
    & "0705010310000a");

  function speed_name return string is
  begin
    if full_speed_c then
      return "FS";
    end if;
    return "LS";
  end function;

  function out_mps return natural is
  begin
    if full_speed_c then
      return 16;
    end if;
    return 8;
  end function;

  -- What the engine is told it runs at, and what it really runs at.
  function clock_rate return natural is
  begin
    if full_speed_c then
      return 48_000_000;
    end if;
    return 12_000_000;
  end function;

  function half_period return time is
  begin
    if full_speed_c then
      return 83333 ps;
    end if;
    return 41667 ps;
  end function;

  constant mps_c: natural := out_mps;

  -- How long the host's millisecond lasts here.
  function host_ms return time is
  begin
    if full_speed_c then
      return 8 ms;
    end if;
    return 1 ms;
  end function;

  constant ms_c: time := host_ms;

  type report_t is
  record
    data: byte_string(0 to 31);
    length: natural;
  end record;

  type report_vector is array (natural range <>) of report_t;

  constant history_length_c: natural := 32;

  function rpt(s: string) return report_t is
    constant b: byte_string := from_hex(s);
    variable ret: report_t;
  begin
    ret.data := (others => x"00");
    ret.data(0 to b'length-1) := b;
    ret.length := b'length;
    return ret;
  end function;

  function fill(v: byte; n: natural) return report_t is
    variable ret: report_t;
  begin
    ret.data := (others => x"00");
    ret.data(0 to n-1) := (others => v);
    ret.length := n;
    return ret;
  end function;

  -- Five-byte ones are the layout of a lamp array output report.
  -- 1010000000 has a CRC16 whose last six bits on the wire are ones,
  -- so a stuffed bit is owed right before the end of packet;
  -- 0000000000 has eight ones in its CRC16; runs of ff stuff all
  -- through the payload.
  constant stream_c: report_vector(0 to 5) := (
    rpt("0013ff0080"),
    rpt("1010000000"),
    rpt("42"),
    fill(x"ff", mps_c),
    rpt("0000000000"),
    fill(x"5a", mps_c - 1));

  constant in_report_c: byte_string(0 to 7) := from_hex("0102030405060708");

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic;
  signal done_s: std_ulogic := '0';

  signal host_c_s: usb_io_c;
  signal host_s_s: usb_io_s;
  signal device_c_s: usb_io_c;
  signal device_s_s: usb_io_s;

  signal identity_s: device_identity_t;
  signal status_s: hid_host_status_t;
  signal report_s: nsl_amba.axi4_stream.bus_t;
  signal output_s: nsl_amba.axi4_stream.bus_t;

  signal present_s: std_ulogic := '1';
  signal report_data_s: byte_string(0 to 7) := (others => x"00");
  signal report_length_s: natural range 0 to 8 := 0;
  signal report_valid_s: std_ulogic := '0';
  signal report_ready_s: std_ulogic;

  signal out_stall_s: std_ulogic := '0';
  signal out_data_s: byte_string(0 to ls_payload_max_c - 1);
  signal out_length_s: natural range 0 to ls_payload_max_c;
  signal out_toggle_s: std_ulogic;
  signal out_valid_s: std_ulogic;

  -- Everything the device accepted, in order.
  signal delivered_count_s: natural := 0;
  signal delivered_s: report_vector(0 to history_length_c - 1);
  signal delivered_toggle_s: std_ulogic_vector(0 to history_length_c - 1);

  signal dropped_count_s: natural := 0;
  signal in_count_s: natural := 0;

begin

  -- Stops once done, as the other speed may take a lot longer.
  clock_gen: process is
  begin
    while done_s = '0'
    loop
      clock_s <= '0';
      wait for half_period;
      clock_s <= '1';
      wait for half_period;
    end loop;
    wait;
  end process;

  done_o <= done_s;

  reset_n_s <= '0', '1' after 500 ns;

  dut: nsl_usb.hid_host.hid_host_engine
    generic map(
      program_c => hid_program(hid_program_config_t'(
        poll_interval_ms => 8,
        report_length => 8,
        configuration_value => 1,
        debounce_ms => 4),
        output_enabled => true,
        output_endpoint => 1),
      clock_rate_c => clock_rate,
      full_speed_c => full_speed_c,
      output_report_length_max_c => mps_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      bus_o => host_c_s,
      bus_i => host_s_s,
      identity_o => identity_s,
      status_o => status_s,
      report_o => report_s.m,
      report_i => report_s.s,
      output_report_i => output_s.m,
      output_report_o => output_s.s
      );

  fs: if full_speed_c generate
    device_c_s.dp <= host_c_s.dm;
    device_c_s.dm <= host_c_s.dp;
    device_c_s.oe <= host_c_s.oe;
    device_c_s.dp_pullup_en <= host_c_s.dp_pullup_en;
    host_s_s.dp <= device_s_s.dm;
    host_s_s.dm <= device_s_s.dp;
  end generate;

  ls: if not full_speed_c generate
    device_c_s <= host_c_s;
    host_s_s <= device_s_s;
  end generate;

  device: nsl_usb.ls_bfm.ls_device_bfm
    generic map(
      device_descriptor_c => device_descriptor_c,
      config_descriptor_c => config_descriptor_c,
      interrupt_ep_c => 1,
      interrupt_out_ep_c => 1,
      interrupt_out_mps_c => mps_c,
      out_nak_count_c => 2,
      out_silent_count_c => 1
      )
    port map(
      host_i => device_c_s,
      host_o => device_s_s,
      present_i => present_s,
      report_data_i => report_data_s,
      report_length_i => report_length_s,
      report_valid_i => report_valid_s,
      report_ready_o => report_ready_s,
      out_stall_i => out_stall_s,
      out_data_o => out_data_s,
      out_length_o => out_length_s,
      out_toggle_o => out_toggle_s,
      out_valid_o => out_valid_s
      );

  report_s.s <= accept(report_cfg_c, true);

  in_collector: process is
  begin
    wait until rising_edge(clock_s);
    if is_valid(report_cfg_c, report_s.m) and is_last(report_cfg_c, report_s.m) then
      in_count_s <= in_count_s + 1;
    end if;
  end process;

  delivered_collector: process is
    variable r: report_t;
  begin
    wait until rising_edge(out_valid_s);
    assert delivered_count_s < history_length_c
      report "Delivery history full"
      severity failure;
    r.data := out_data_s(0 to 31);
    r.length := out_length_s;
    delivered_s(delivered_count_s) <= r;
    delivered_toggle_s(delivered_count_s) <= out_toggle_s;
    delivered_count_s <= delivered_count_s + 1;
  end process;

  drop_counter: process is
  begin
    wait until rising_edge(clock_s);
    if status_s.output_dropped = '1' then
      dropped_count_s <= dropped_count_s + 1;
    end if;
  end process;

  watchdog_check: process is
  begin
    wait until rising_edge(clock_s);
    assert status_s.error = '0'
      report speed_name & ": protocol watchdog fired"
      severity failure;
  end process;

  stim: process is
    variable seen, dropped: natural;
    variable expected_toggle: std_ulogic := '0';

    procedure push(r: report_t) is
    begin
      packet_send(report_cfg_c, clock_s, output_s.s, output_s.m,
                  r.data(0 to r.length-1));
    end procedure;

    procedure check_delivery(r: report_t; what: string) is
      variable d: report_t;
    begin
      if delivered_count_s <= seen then
        wait until delivered_count_s > seen for 100 * ms_c;
      end if;
      assert delivered_count_s > seen
        report speed_name & ": " & what & " was not delivered"
        severity failure;

      d := delivered_s(seen);
      assert d.length = r.length
        and d.data(0 to r.length-1) = r.data(0 to r.length-1)
        report speed_name & ": " & what & " delivered as "
        & to_hex_string(d.data(0 to d.length-1))
        & ", sent " & to_hex_string(r.data(0 to r.length-1))
        severity failure;

      assert delivered_toggle_s(seen) = expected_toggle
        report speed_name & ": " & what & " delivered with the wrong toggle"
        severity failure;
      expected_toggle := not expected_toggle;
      seen := seen + 1;
    end procedure;

    procedure check_drop(dropped: natural; what: string) is
    begin
      if dropped_count_s = dropped then
        wait until dropped_count_s /= dropped for 100 * ms_c;
      end if;
      assert dropped_count_s = dropped + 1
        report speed_name & ": " & what & " was not dropped"
        severity failure;
    end procedure;

    procedure enumerate is
    begin
      wait until identity_s.valid for 4 sec;
      assert identity_s.valid
        report speed_name & ": device did not enumerate"
        severity failure;
      assert identity_s.vid = x"1500" and identity_s.pid = x"0ec1"
        report speed_name & ": identity came back as "
        & to_hex_string(std_ulogic_vector(identity_s.vid)) & ":"
        & to_hex_string(std_ulogic_vector(identity_s.pid))
        severity failure;
    end procedure;

  begin
    output_s.m <= transfer_defaults(report_cfg_c);
    seen := 0;

    log_info(speed_name & ": * Enumeration");
    enumerate;

    log_info(speed_name & ": * Reports back to back, IN polling alongside");
    wait until falling_edge(clock_s);
    report_data_s <= in_report_c;
    report_length_s <= 8;
    report_valid_s <= '1';

    for i in stream_c'range
    loop
      push(stream_c(i));
    end loop;

    for i in stream_c'range
    loop
      check_delivery(stream_c(i), "report " & to_string(i));
    end loop;

    assert in_count_s /= 0
      report speed_name & ": no input report came through while sending"
      severity failure;
    wait until falling_edge(clock_s);
    report_valid_s <= '0';

    log_info(speed_name & ": * Report too long for the buffer");
    dropped := dropped_count_s;
    push(fill(x"77", mps_c + 1));
    check_drop(dropped, "overlong report");
    assert not status_s.output_pending
      report speed_name & ": overlong report left something pending"
      severity failure;
    push(rpt("0102030405"));
    check_delivery(rpt("0102030405"), "report after an overlong one");

    log_info(speed_name & ": * STALL");
    wait until falling_edge(clock_s);
    out_stall_s <= '1';
    dropped := dropped_count_s;
    push(rpt("0506070809"));
    check_drop(dropped, "STALLed report");
    assert delivered_count_s = seen
      report speed_name & ": STALLed report was delivered"
      severity failure;
    wait until falling_edge(clock_s);
    out_stall_s <= '0';
    push(rpt("0a0b0c0d0e"));
    check_delivery(rpt("0a0b0c0d0e"), "report after a STALL");

    log_info(speed_name & ": * Device going away with a report pending");
    -- Leave the toggle at DATA1 so that its reset is visible.
    if expected_toggle = '0' then
      push(rpt("11"));
      check_delivery(rpt("11"), "toggle-adjusting report");
    end if;

    dropped := dropped_count_s;
    push(rpt("2222222222"));
    assert status_s.output_pending
      report speed_name & ": report did not become pending"
      severity failure;

    -- A device unplugged while the host waits for its answer leaves
    -- the host waiting for an idle bus that never comes, until its
    -- watchdog restarts it.  That is not what is looked at here, so
    -- unplug between two millisecond ticks' worth of traffic: after
    -- the report's first attempt, which the device lets go
    -- unanswered, and the IN poll that follows it.
    wait until host_c_s.oe = '1';
    loop
      if host_c_s.oe = '1' then
        wait until host_c_s.oe = '0';
      end if;
      wait until host_c_s.oe = '1' for ms_c * 3 / 10;
      exit when host_c_s.oe = '0';
    end loop;
    present_s <= '0';

    check_drop(dropped, "report pending on disconnect");
    assert not identity_s.valid
      report speed_name & ": disconnect was not noticed"
      severity failure;

    wait for 5 * ms_c;
    present_s <= '1';
    enumerate;
    expected_toggle := '0';

    assert delivered_count_s = seen
      report speed_name & ": a dropped report reached the device"
      severity failure;

    push(rpt("3333333333"));
    check_delivery(rpt("3333333333"), "report after re-enumeration");
    push(rpt("4444444444"));
    check_delivery(rpt("4444444444"), "second report after re-enumeration");

    log_info(speed_name & ": * Done");
    done_s <= '1';
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;
library nsl_simulation;

entity tb is
end entity;

architecture beh of tb is
  signal done_s: std_ulogic_vector(0 to 1);
begin
  ls: entity work.output_test
    generic map(full_speed_c => false)
    port map(done_o => done_s(0));

  fs: entity work.output_test
    generic map(full_speed_c => true)
    port map(done_o => done_s(1));

  finish: process is
  begin
    wait until done_s = "11";
    nsl_simulation.control.terminate(0);
    wait;
  end process;
end architecture;
