library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_output is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i   : in std_ulogic_vector(1 downto 0);
    dd_o  : out std_ulogic
    );
end entity;

architecture gowin of ddr_output is

  component ODDR is
    GENERIC ( 
      TXCLK_POL : bit := '0'; --'0':Rising edge output; '1':Falling edge output        
      CONSTANT INIT : std_logic := '0' 
      );	
    PORT ( 
      Q0 : OUT std_logic;	
      Q1 : OUT std_logic;	
      D0 : IN std_logic;
      D1 : IN std_logic;
      TX : IN std_logic;
      CLK : IN std_logic
      );	
  end component;

begin

  -- Gowin ODDR gate behavior:
  --            __    __    __    __    __    __    __    __
  --  Clock  __/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__
  --  D0        X  A  X  C  X  E  X  G  X  I  X  K  X
  --  D1        X  B  X  D  X  F  X  H  X  J  X  L  X
  --  TX        X  M  X  N  X  O  X  P  X  Q  X  R  X
  --  Dd0_0           X  A  X  C  X  E  X  G  X  I  X  K  X        |
  --  Dd1_0           X  B  X  D  X  F  X  H  X  J  X  L  X        |
  --  Ttx0            X  M  X  N  X  O  X  P  X  Q  X  R  X        |
  --  Dd0_1                 X  A  X  C  X  E  X  G  X  I  X  K  X  | Internal
  --  Dd1_1                 X  B  X  D  X  F  X  H  X  J  X  L  X  | signals
  --  Ttx1                  X  M  X  N  X  O  X  P  X  Q  X  R  X  |
  --  Dd0_2              X  A  X  C  X  E  X  G  X  I  X  K  X     |
  --  Dd1_2                 X  B  X  D  X  F  X  H  X  J  X  L  X  |
  --  DT1                X  M  X  N  X  O  X  P  X  Q  X  R  X     |
  --  DT0                   X  M  X  N  X  O  X  P  X  Q  X  R  X  |
  --            __    __    __    __    __    __    __    __
  --  Clock  __/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__
  --  Q0                   XA X BXC XD XE XF XG XH XI XJ XK XL X
  --  Q1/tclkpol=0          X  M  X  N  X  O  X  P  X  Q  X  R  X
  --  Q1/tclkpol=1       X  M  X  N  X  O  X  P  X  Q  X  R  X
  
  inst: oddr
    port map (
      q0 => dd_o,
      q1 => open,
      clk => clock_i.p,
      tx => '1',
      d0 => d_i(0),
      d1 => d_i(1)
      );

end architecture;
