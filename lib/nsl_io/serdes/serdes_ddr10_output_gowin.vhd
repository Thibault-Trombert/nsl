library ieee;
use ieee.std_logic_1164.all;

entity serdes_ddr10_output is
  generic(
    left_to_right_c : boolean := false
    );
  port(
    bit_clock_i : in std_ulogic;
    word_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    parallel_i : in std_ulogic_vector(0 to 9);
    serial_o : out std_ulogic
    );
end entity;

architecture gowin of serdes_ddr10_output is

  signal d_s: std_ulogic_vector(0 to 9);
  signal reset_s: std_ulogic;

  COMPONENT OSER10
    GENERIC (
      GSREN:string:="false";
      LSREN:string:="true"
      );
    PORT(
      Q:OUT std_logic;
      D0:IN std_logic;
      D1:IN std_logic;
      D2:IN std_logic;
      D3:IN std_logic;
      D4:IN std_logic;
      D5:IN std_logic;
      D6:IN std_logic;
      D7:IN std_logic;
      D8:IN std_logic;
      D9:IN std_logic;
      FCLK:IN std_logic;
      PCLK:IN std_logic;
      RESET:IN std_logic
      );
  END COMPONENT;
  
begin

  reset_s <= not reset_n_i;
  
  ltr: if left_to_right_c
  generate
    d <= parallel_i;
  end generate;

  rtl: if not left_to_right_c
  generate
    in_map: for i in 0 to 9
    generate
      d(9-i) <= parallel_i(i);
    end generate;
  end generate;

  inst: OSER10
    port map(
      q => serial_o,
      d0 => d_s(0),
      d1 => d_s(1),
      d2 => d_s(2),
      d3 => d_s(3),
      d4 => d_s(4),
      d5 => d_s(5),
      d6 => d_s(6),
      d7 => d_s(7),
      d8 => d_s(8),
      d9 => d_s(9),
      fclk => bit_clock_i,
      pclk => word_clock_i,
      reset => reset_s
      );
  
end architecture;
