library ieee;
use ieee.std_logic_1164.all;

library nsl_data;

entity serdes_input is
  generic(
    left_first_c : boolean := false;
    ddr_mode_c : boolean := false;
    from_delay_c : boolean := false;
    ratio_c : positive
    );
  port(
    serial_clock_i : in std_ulogic;
    parallel_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    serial_i : in std_ulogic;
    parallel_o : out std_ulogic_vector(0 to ratio_c-1);

    bitslip_i : in std_ulogic;
    mark_o : out std_ulogic
    );
end entity;

architecture simulation of serdes_input is

  signal bitslip_s : boolean;
  signal word_s: std_ulogic_vector(0 to ratio_c-1);
  signal mark_ctr_s: integer range 0 to ratio_c-1;

begin

  assert (not ddr_mode_c) or ((ratio_c mod 2) = 0)
    report "DDR can only support even ratios"
    severity failure;

  assert ratio_c >= 3
    report "Serdes is only for parallel >= 3"
    severity failure;

  d_present: process(parallel_clock_i, reset_n_i) is
  begin
    if rising_edge(parallel_clock_i) then
      bitslip_s <= bitslip_i = '1';
      if bitslip_i = '1' then
        if mark_ctr_s = 0 then
          mark_ctr_s <= ratio_c-1;
        else
          mark_ctr_s <= mark_ctr_s - 1;
        end if;
      end if;
      
      if left_first_c then
        parallel_o <= word_s;
      else
        for i in 0 to ratio_c-1
        loop
          parallel_o(ratio_c-1-i) <= word_s(i);
        end loop;
      end if;
    end if;

    if reset_n_i = '0' then
      mark_ctr_s <= 0;
    end if;
  end process;

  mark_o <= '1' when mark_ctr_s = 0 else '0';
  
  sdr_mode: if not ddr_mode_c
  generate
    signal bits_left_s: integer range 0 to ratio_c-1;
    signal shreg_s: std_ulogic_vector(0 to ratio_c-1);
  begin
    ingress: process(serial_clock_i, reset_n_i) is
    begin
      if rising_edge(serial_clock_i) then
        shreg_s <= shreg_s(1 to ratio_c-1) & serial_i;

        if bits_left_s /= 0 then
          bits_left_s <= bits_left_s - 1;
        else
          word_s <= shreg_s;
          if bitslip_s then
            bits_left_s <= ratio_c-2;
          else
            bits_left_s <= ratio_c-1;
          end if;
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
    ingress: process(serial_clock_i, reset_n_i) is
    begin
      if falling_edge(serial_clock_i) or rising_edge(serial_clock_i) then
        shreg_s <= shreg_s(1 to ratio_c-1) & serial_i;

        if bits_left_s /= 0 then
          bits_left_s <= bits_left_s - 1;
        else
          word_s <= shreg_s;
          if bitslip_s then
            bits_left_s <= ratio_c-2;
          else
            bits_left_s <= ratio_c-1;
          end if;
        end if;
      end if;

      if reset_n_i = '0' then
        bits_left_s <= 0;
      end if;
    end process;
  end generate;

end architecture;
