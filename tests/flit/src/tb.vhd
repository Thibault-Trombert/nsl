library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;
use nsl.util.all;

library testing;
use testing.fifo.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 downto 0);

  signal s_framed_val : fifo_framed_cmd;
  signal s_framed_ack : fifo_framed_rsp;

  signal s_flit_val : flit_cmd;
  signal s_flit_ack : flit_ack;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.fifo.fifo_framed_file_reader
    generic map(
      filename => "framed.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_framed_val,
      p_out_ack => s_framed_ack
      );

  check: testing.fifo.fifo_file_checker
    generic map(
      filename => "flit.txt",
      width => 8
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_full_n => s_flit_ack.ack,
      p_write => s_flit_val.val,
      p_data => s_flit_val.data,
      p_done => s_done(0)
      );

  fifo: nsl.flit.flit_fifo_committable
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_framed_val,
      p_in_ack => s_framed_ack,
      p_out_val => s_flit_val,
      p_out_ack => s_flit_ack
      );
  
  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;
  
end;
