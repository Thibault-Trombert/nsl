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

-- Gearbox V2C testbench
--
-- Tests the variable-to-constant gearbox by:
-- 1. Input process: feeds preamble zeros, marker, then PRBS data at variable rate
-- 2. Output process: finds marker, then verifies PRBS

entity tb is
  generic(
    input_max_width_c : positive := 5;
    output_width_c    : positive := 10
    );
end entity;

architecture arch of tb is

  signal clock_s   : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s    : std_ulogic_vector(0 to 1);

  signal in_s       : std_ulogic_vector(0 to input_max_width_c - 1);
  signal in_len_s   : integer range 0 to input_max_width_c;
  signal out_valid_s : std_ulogic;
  signal out_s      : std_ulogic_vector(0 to output_width_c - 1);

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

  dut: gearbox_v2c
    generic map(
      input_max_width_c => input_max_width_c,
      output_width_c    => output_width_c
      )
    port map(
      clock_i     => clock_s,
      reset_n_i   => reset_n_s,
      in_i        => in_s,
      in_len_i    => in_len_s,
      out_valid_o => out_valid_s,
      out_o       => out_s
      );

  -- Input generation process
  input_proc: process
    constant data_poly_c : prbs_state := prbs15;
    constant data_init_c : prbs_state(14 downto 0) := (others => '1');
    variable data_state  : prbs_state(14 downto 0);

    constant len_poly_c : prbs_state := prbs7;
    constant len_init_c : prbs_state(6 downto 0) := (others => '1');
    variable len_state  : prbs_state(6 downto 0);

    variable input_bits  : std_ulogic_vector(0 to input_max_width_c - 1);
    variable len_bits    : std_ulogic_vector(0 to 7);
    variable bits_sent   : natural := 0;

    procedure put(data : std_ulogic_vector(0 to input_max_width_c - 1);
                  len  : integer range 0 to input_max_width_c) is
    begin
      in_s <= data;
      in_len_s <= len;
      wait until rising_edge(clock_s);
      wait for 1 ns;
    end procedure;

  begin
    done_s(0) <= '0';
    in_s <= (others => '0');
    in_len_s <= 0;
    data_state := data_init_c;
    len_state := len_init_c;

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    wait for 1 ns;

    log_info("=== Input Process Started ===");

    -- Phase 1: Feed preamble (zeros at full width)
    log_info("Feeding preamble (zeros)...");
    for i in 0 to preamble_words_c - 1 loop
      put((others => '0'), input_max_width_c);
    end loop;

    -- Phase 2: Feed marker (word ending with '1')
    log_info("Feeding marker...");
    input_bits := (others => '0');
    input_bits(input_bits'right) := '1';
    put(input_bits, input_max_width_c);

    -- Phase 3: Feed PRBS data at variable rate
    log_info("Feeding PRBS data...");
    while bits_sent < total_bits_c + output_width_c * 10 loop
      -- Generate variable length from len PRBS (0 to input_max_width_c)
      len_bits := prbs_bit_string(len_state, len_poly_c, len_bits'length);
      len_state := prbs_forward(len_state, len_poly_c, len_bits'length);

      -- Map to 0..input_max_width_c range
      input_bits := (others => '0');
      for len in 0 to input_max_width_c loop
        if to_integer(unsigned(len_bits)) mod (input_max_width_c + 1) = len then
          if len > 0 then
            input_bits(0 to len - 1) := prbs_bit_string(data_state, data_poly_c, len);
            data_state := prbs_forward(data_state, data_poly_c, len);
            bits_sent := bits_sent + len;
          end if;
          put(input_bits, len);
        end if;
      end loop;
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
    variable expected     : std_ulogic_vector(0 to output_width_c - 1);
    variable bits_verified : natural := 0;
    variable marker_pos   : integer := -1;
    variable partial_len  : integer;
    variable partial_exp  : std_ulogic_vector(0 to output_width_c - 1);
  begin
    done_s(1) <= '0';
    verify_state := data_init_c;

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    wait for 1 ns;

    log_info("=== Output Process Started ===");

    -- Phase 1: Wait for valid output and find marker
    log_info("Searching for marker...");
    loop
      wait until rising_edge(clock_s);
      wait for 1 ns;

      if out_valid_s = '1' then
        -- Look for '1' in output
        marker_pos := -1;
        for i in 0 to output_width_c - 1 loop
          if out_s(i) = '1' then
            marker_pos := i;
            exit;
          end if;
        end loop;

        if marker_pos >= 0 then
          log_info("Marker found at position " & to_string(marker_pos));
          exit;
        end if;
      end if;
    end loop;

    -- Phase 2: Verify PRBS
    log_info("Starting PRBS verification...");

    -- First partial word after marker (if any bits remain in this word)
    if marker_pos < output_width_c - 1 then
      partial_len := output_width_c - 1 - marker_pos;
      partial_exp(0 to partial_len - 1) := prbs_bit_string(verify_state, data_poly_c, partial_len);

      if out_s(marker_pos + 1 to output_width_c - 1) /= partial_exp(0 to partial_len - 1) then
        log_error("PRBS mismatch in first partial word: expected " &
                  to_string(partial_exp(0 to partial_len - 1)) &
                  ", got " & to_string(out_s(marker_pos + 1 to output_width_c - 1)));
        assert false report "PRBS mismatch" severity failure;
      end if;

      verify_state := prbs_forward(verify_state, data_poly_c, partial_len);
      bits_verified := bits_verified + partial_len;
    end if;

    -- Full words
    while bits_verified < total_bits_c loop
      wait until rising_edge(clock_s);
      wait for 1 ns;

      if out_valid_s = '1' then
        expected := prbs_bit_string(verify_state, data_poly_c, output_width_c);

        if out_s /= expected then
          log_error("PRBS mismatch at bit " & to_string(bits_verified) &
                    ": expected " & to_string(expected) &
                    ", got " & to_string(out_s));
          assert false report "PRBS mismatch" severity failure;
        end if;

        verify_state := prbs_forward(verify_state, data_poly_c, output_width_c);
        bits_verified := bits_verified + output_width_c;

        -- Progress report
        if bits_verified mod 1000 < output_width_c then
          log_info("Verified " & to_string(bits_verified) & " bits...");
        end if;
      end if;
    end loop;

    log_info("=== TEST PASSED ===");
    log_info("Total bits verified: " & to_string(bits_verified));

    done_s(1) <= '1';
    wait;
  end process;

end architecture;
