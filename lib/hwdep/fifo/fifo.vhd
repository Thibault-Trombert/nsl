library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

package fifo is

  component fifo_2p
    generic(
      data_width : integer;
      depth      : integer;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_valid  : in  std_ulogic;
      p_in_ready : out std_ulogic;

      p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
      p_out_ready    : in  std_ulogic;
      p_out_valid : out std_ulogic
      );
  end component;

  component fifo_write_pointer is
    generic(
      ptr_width : natural;
      wrap_count: integer
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_valid    : in  std_ulogic;
      p_ready    : out std_ulogic;

      p_peer_ptr : in  unsigned(ptr_width-1 downto 0);
      p_mem_ptr  : out unsigned(ptr_width-1 downto 0);
      p_write    : out std_ulogic
      );
  end component;

  component fifo_read_pointer is
    generic(
      ptr_width : natural;
      wrap_count: integer
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_ready    : in  std_ulogic;
      p_valid    : out std_ulogic;

      p_peer_ptr : in  unsigned(ptr_width-1 downto 0);
      p_mem_ptr  : out unsigned(ptr_width-1 downto 0);
      p_read     : out std_ulogic
      );
  end component;

end package fifo;
