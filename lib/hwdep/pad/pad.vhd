library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;
use signalling.diff.all;

package pad is

  component pad_diff_clock_input
    generic(
      diff_term : boolean := true;
      invert    : boolean := false
      );
    port(
      p_pad : in  diff_pair;
      p_clk : out diff_pair
      );
  end component;

  component pad_diff_input
    generic(
      diff_term : boolean := true;
      is_clock : boolean := false;
      invert : boolean := false
      );
    port(
      p_diff : in diff_pair;
      p_se : out std_ulogic
      );
  end component;

  component pad_diff_output
    generic(
      is_clock : boolean := false
      );
    port(
      p_se : in std_ulogic;
      p_diff : out diff_pair
      );
  end component;

end package pad;
