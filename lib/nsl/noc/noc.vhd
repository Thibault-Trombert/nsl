library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl;
use nsl.fifo.all;

package noc is

  type noc_routing_table is array(natural range 0 to 15) of natural;

  component noc_router is
    generic(
      in_port_count : natural;
      out_port_count : natural;
      routing_table : noc_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out fifo_framed_rsp_array(in_port_count-1 downto 0);

      p_out_val   : out fifo_framed_cmd_array(out_port_count-1 downto 0);
      p_out_ack   : in fifo_framed_rsp_array(out_port_count-1 downto 0)
      );
  end component;

  component noc_router_inbound is
    generic(
      out_port_count : natural;
      routing_table : noc_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd;
      p_in_ack   : out fifo_framed_rsp;

      p_out_val  : out fifo_framed_cmd;
      p_out_ack  : in fifo_framed_rsp_array(out_port_count-1 downto 0);
      
      p_select : out std_ulogic_vector(out_port_count-1 downto 0)
      );
  end component;

  component noc_router_outbound is
    generic(
      in_port_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out fifo_framed_rsp;

      p_out_val  : out fifo_framed_cmd;
      p_out_ack  : in fifo_framed_rsp;

      p_select : in std_ulogic_vector(in_port_count-1 downto 0)
      );
  end component;

end package noc;
