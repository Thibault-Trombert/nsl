library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;

entity fifo_framed_router_inbound is
  generic(
    out_port_count : natural;
    routing_table : nsl.fifo.fifo_framed_routing_table
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in nsl.fifo.fifo_framed_cmd;
    p_in_ack   : out nsl.fifo.fifo_framed_rsp;

    p_out_val  : out nsl.fifo.fifo_framed_cmd;
    p_out_ack  : in nsl.fifo.fifo_framed_rsp_array(out_port_count-1 downto 0);

    p_request  : out std_ulogic_vector(out_port_count-1 downto 0);
    p_selected : in  std_ulogic_vector(out_port_count-1 downto 0)
    );
end entity;

architecture rtl of fifo_framed_router_inbound is

  type state_t is (
    STATE_RESET,
    STATE_IDLE,
    STATE_FLUSH_HEADER,
    STATE_PASSTHROUGH
    );

  type regs_t is record
    state : state_t;
    selected : natural range 0 to out_port_count-1;
    header : std_ulogic_vector(7 downto 0);
  end record;

  signal r, rin: regs_t;

begin

  clk: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(p_in_val, p_out_ack, r, p_selected)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_IDLE;
        rin.selected <= 0;

      when STATE_IDLE =>
        if p_in_val.val = '1' then
          rin.state <= STATE_FLUSH_HEADER;
          rin.header <= p_in_val.data;
          rin.selected <= routing_table(to_integer(unsigned(p_in_val.data(3 downto 0))));
        end if;

      when STATE_FLUSH_HEADER =>
        if p_out_ack(r.selected).ack = '1' and p_selected(r.selected) = '1' then
          rin.state <= STATE_PASSTHROUGH;
        end if;

      when STATE_PASSTHROUGH =>
        if p_out_ack(r.selected).ack = '1'
          and p_in_val.val = '1'
          and p_in_val.more = '0'
          and p_selected(r.selected) = '1' then
          rin.state <= STATE_IDLE;
        end if;

    end case;
  end process;

  outputs: process(r, p_in_val, p_out_ack, p_selected)
  begin
    p_in_ack.ack <= '0';
    p_out_val.val <= '0';
    p_out_val.more <= '-';
    p_out_val.data <= (others => '-');
    p_request <= (others => '0');

    case r.state is
      when STATE_RESET =>
        null;

      when STATE_IDLE =>
        p_in_ack.ack <= '1';

      when STATE_FLUSH_HEADER =>
        p_out_val.val <= '1';
        p_out_val.more <= '1';
        p_out_val.data <= r.header;
        p_request(r.selected) <= '1';

      when STATE_PASSTHROUGH =>
        p_in_ack.ack <= p_out_ack(r.selected).ack and p_selected(r.selected);
        p_out_val.val <= p_in_val.val and p_selected(r.selected);
        p_out_val.more <= p_in_val.more;
        p_out_val.data <= p_in_val.data;
        p_request(r.selected) <= '1';
    end case;
  end process;

end architecture;
