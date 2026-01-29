library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

library nsl_logic;
use nsl_logic.gearbox.all;

library nsl_data;
use nsl_data.text.all;
use nsl_data.prbs.all;

-- Gearbox C2V testbench
--
-- Tests the constant-to-variable gearbox by:
-- 1. Input process: feeds preamble zeros, then PRBS data
-- 2. Output process: searches for marker, then verifies PRBS

entity tb is
  generic(
    input_width_c      : positive := 10;
    output_max_width_c : positive := 5
    );
end entity;

architecture arch of tb is

  signal clock_s   : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s    : std_ulogic_vector(0 to 1);

  signal in_s       : std_ulogic_vector(0 to input_width_c - 1);
  signal in_ready_s : std_ulogic;
  signal out_len_s  : integer range 0 to output_max_width_c;
  signal out_s      : std_ulogic_vector(0 to output_max_width_c - 1);

  constant preamble_words_c : natural := 4;
  constant total_bits_c     : natural := 10000;

begin

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count  => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration  => (others => 100 ns),
      clock_o(0)      => clock_s,
      reset_n_o(0)    => reset_n_s,
      done_i          => done_s
      );

  dut: gearbox_c2v
    generic map(
      input_width_c      => input_width_c,
      output_max_width_c => output_max_width_c
      )
    port map(
      clock_i    => clock_s,
      reset_n_i  => reset_n_s,
      in_i       => in_s,
      in_ready_o => in_ready_s,
      out_len_i  => out_len_s,
      out_o      => out_s
      );

  -- Input generation process
  input_proc: process
    constant data_poly_c : prbs_state := prbs15;
    constant data_init_c : prbs_state(14 downto 0) := (others => '1');
    variable data_state  : prbs_state(14 downto 0);
    variable input_bits  : std_ulogic_vector(0 to input_width_c - 1);

    procedure put(data : std_ulogic_vector(0 to input_width_c - 1)) is
    begin
      in_s <= data;
      loop
        wait until rising_edge(clock_s);
        if in_ready_s = '1' then
          exit;
        end if;
      end loop;
      wait for 1 ns;
    end procedure;

  begin
    done_s(0) <= '0';
    in_s <= (others => '0');
    data_state := data_init_c;

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    wait for 1 ns;

    log_info("=== Input Process Started ===");

    -- Phase 1: Feed preamble (zeros)
    log_info("Feeding preamble (zeros)...");
    for i in 0 to preamble_words_c - 1 loop
      put((others => '0'));
    end loop;

    input_bits := (others => '0');
    input_bits(input_bits'right) := '1';
    put(input_bits);

    -- Phase 2: Feed PRBS data continuously
    log_info("Feeding PRBS data...");
    for word in 0 to (total_bits_c / input_width_c) + 9 loop
      input_bits := prbs_bit_string(data_state, data_poly_c, input_bits'length);
      data_state := prbs_forward(data_state, data_poly_c, input_bits'length);
      put(input_bits);
    end loop;

    log_info("Input process done");
    done_s(0) <= '1';
    wait;
  end process;

  -- Output verification process
  output_proc: process
    constant data_poly_c : prbs_state := prbs15;
    constant data_init_c : prbs_state(14 downto 0) := (others => '1');
    variable verify_state : prbs_state(14 downto 0);

    constant len_poly_c : prbs_state := prbs7;
    constant len_init_c : prbs_state(6 downto 0) := (others => '1');
    variable len_state  : prbs_state(6 downto 0);

    variable len_bits   : std_ulogic_vector(0 to 7);
    variable len_val    : integer;
    variable expected   : std_ulogic_vector(0 to output_max_width_c-1);
    variable actual     : std_ulogic_vector(0 to output_max_width_c-1);
    variable bits_verified : natural := 0;
    variable cycle_count   : natural := 0;
  begin
    done_s(1) <= '0';
    out_len_s <= 0;
    verify_state := data_init_c;
    len_state := len_init_c;

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    wait for 1 ns;

    log_info("=== Output Process Started ===");

    -- Phase 1: Consume preamble zeros (drain initial garbage)
    log_info("Draining preamble...");
    out_len_s <= 1;
    for i in 0 to input_width_c * 3
    loop
      wait until rising_edge(clock_s);
      wait for 1 ns;
    end loop;

    -- Phase 2: Search for PRBS start (first '1')
    log_info("Searching for PRBS start (first '1')...");
    loop
      out_len_s <= 1;
      wait until rising_edge(clock_s);
      if out_s(0) = '1' then
        exit;
      end if;
    end loop;

    log_info("PRBS start found, starting verification...");

    -- Phase 3: Main verification loop
    while bits_verified < total_bits_c loop
      -- Generate output length from len PRBS (0-5)
      len_bits := prbs_bit_string(len_state, len_poly_c, len_bits'length);
      len_state := prbs_forward(len_state, len_poly_c, len_bits'length);
      len_val := to_integer(unsigned(len_bits)) mod (output_max_width_c + 1);

      -- Set consumption amount
      out_len_s <= len_val;

      -- Verify current output (before consumption)
      if len_val > 0 then
        expected(0 to len_val-1) := prbs_bit_string(verify_state, data_poly_c, len_val);
        verify_state := prbs_forward(verify_state, data_poly_c, len_val);
        actual := out_s;

        if actual(0 to len_val-1) /= expected(0 to len_val-1) then
          log_error("Bit mismatch at verified bit " & to_string(bits_verified) &
                    ": expected " & to_string(expected(0 to len_val-1)) &
                    ", got " & to_string(actual(0 to len_val-1)));
          assert false report "Bit mismatch" severity failure;
        end if;
        bits_verified := bits_verified + len_val;
      end if;

      -- Wait for clock edge
      wait until rising_edge(clock_s);
      wait for 1 ns;
      cycle_count := cycle_count + 1;

      -- Progress report every 1000 bits
      if bits_verified mod 1000 = 0 and bits_verified > 0 and len_val > 0 then
        log_info("Verified " & to_string(bits_verified) & " bits...");
      end if;
    end loop;

    log_info("=== TEST PASSED ===");
    log_info("Total cycles: " & to_string(cycle_count));
    log_info("Total bits verified: " & to_string(bits_verified));

    done_s(1) <= '1';
    wait;
  end process;

end architecture;
