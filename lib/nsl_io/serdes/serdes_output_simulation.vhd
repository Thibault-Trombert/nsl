library ieee;
use ieee.std_logic_1164.all;

entity serdes_output is
  generic(
    left_first_c : boolean := false;
    ddr_mode_c : boolean := false;
    to_delay_c : boolean := false;
    ratio_c : positive
    );
  port(
    serial_clock_i : in std_ulogic;
    parallel_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    parallel_i : in std_ulogic_vector(0 to ratio_c-1);
    serial_o : out std_ulogic
    );
end entity;

architecture simulation of serdes_output is

  -- Sent from left to right, always
  signal word_s: std_ulogic_vector(0 to ratio_c-1);

begin

  assert (not ddr_mode_c) or ((ratio_c mod 2) = 0)
    report "DDR can only support even ratios"
    severity failure;

  assert ratio_c >= 3
    report "Serdes is only for parallel >= 3"
    severity failure;

  word_s_take: process(parallel_clock_i) is
  begin
    if rising_edge(parallel_clock_i) then
      if left_first_c then
        word_s <= parallel_i;
      else
        for i in 0 to ratio_c-1
        loop
          word_s(ratio_c-1-i) <= parallel_i(i);
        end loop;
      end if;
    end if;
  end process;

  sdr_mode: if not ddr_mode_c
  generate
    signal shreg_s: std_ulogic_vector(0 to ratio_c-1);
    signal bits_left_s: integer range 0 to ratio_c;
  begin
    shift: process(serial_clock_i, reset_n_i) is
    begin
      if rising_edge(serial_clock_i) then
        serial_o <= shreg_s(0);
        shreg_s <= shreg_s(1 to ratio_c-1) & "-";
        if bits_left_s = 0 then
          bits_left_s <= ratio_c-1;
          shreg_s <= word_s;
        else
          bits_left_s <= bits_left_s - 1;
        end if;
      end if;

      if reset_n_i = '0' then
        bits_left_s <= 0;
      end if;
    end process;
  end generate;

  ddr_mode: if ddr_mode_c
  generate
    signal shreg_s: std_ulogic_vector(0 to ratio_c-1);
    signal bits_left_s: integer range 0 to ratio_c;
  begin
    shift: process(serial_clock_i, reset_n_i) is
    begin
      if rising_edge(serial_clock_i) or falling_edge(serial_clock_i) then
        serial_o <= shreg_s(0);
        shreg_s <= shreg_s(1 to ratio_c-1) & "-";
        if bits_left_s = 0 then
          bits_left_s <= ratio_c-1;
          shreg_s <= word_s;
        else
          bits_left_s <= bits_left_s - 1;
        end if;
      end if;

      if reset_n_i = '0' then
        bits_left_s <= 0;
      end if;
    end process;
  end generate;

end architecture;
