library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package swd is

  component swdap
    port (
      p_swclk : in std_logic;
      p_swdio : inout std_logic;

      p_dap_a : out unsigned(1 downto 0);
      p_dap_ad : out std_logic;
      p_dap_rdata : in unsigned(31 downto 0);
      p_dap_ready : in std_logic;
      p_dap_ren : out std_logic;
      p_dap_wdata : out unsigned(31 downto 0);
      p_dap_wen : out std_logic
      );
  end component;

end package swd;
