library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;
use nsl.ti.all;

entity ti_framed_easyscale is
  generic(
    p_clk_rate : natural
    );
  port(
    p_resetn    : in std_ulogic;
    p_clk       : in std_ulogic;

    p_easyscale: inout std_logic;

    p_cmd_val  : in  nsl.framed.framed_req;
    p_cmd_ack  : out nsl.framed.framed_ack;

    p_rsp_val : out nsl.framed.framed_req;
    p_rsp_ack : in  nsl.framed.framed_ack
    );
end entity;

architecture beh of ti_framed_easyscale is

  type state_e is (
    STATE_RESET,
    STATE_DADDR_GET,
    STATE_DATA_GET,
    STATE_EXECUTE,
    STATE_WAIT,
    STATE_ACK_PUT
    );
  
  type regs_t is record
    state : state_e;
    daddr : framed_data_t;
    data  : framed_data_t;
    ack   : std_ulogic;
    more  : std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal s_busy, s_start, s_ack : std_ulogic;
  
begin

  ez: ti_easyscale
    generic map(
      p_clk_rate => p_clk_rate
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_easyscale => p_easyscale,
      p_dev_addr => r.daddr,
      p_ack_req => '1',
      p_reg_addr => r.data(6 downto 5),
      p_data => r.data(4 downto 0),
      p_start => s_start,
      p_busy => s_busy,
      p_dev_ack => s_ack
      );
  
  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, s_busy, s_ack, p_cmd_val, p_rsp_ack)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_DADDR_GET;

      when STATE_DADDR_GET =>
        if p_cmd_val.val = '1' then
          rin.state <= STATE_DATA_GET;
          rin.daddr <= p_cmd_val.data;
        end if;

      when STATE_DATA_GET =>
        if p_cmd_val.val = '1' then
          rin.more <= p_cmd_val.more;
          rin.state <= STATE_EXECUTE;
          rin.data <= p_cmd_val.data;
        end if;

      when STATE_EXECUTE =>
        if s_busy = '1' then
          rin.state <= STATE_WAIT;
        end if;

      when STATE_WAIT =>
        if s_busy = '0' then
          rin.state <= STATE_ACK_PUT;
          rin.ack <= s_ack;
        end if;

      when STATE_ACK_PUT =>
        if p_rsp_ack.ack = '1' then
          rin.state <= STATE_DADDR_GET;
        end if;

    end case;
  end process;

  moore: process(r)
  begin
    p_cmd_ack.ack <= '0';
    p_rsp_val.val <= '0';
    p_rsp_val.data <= (others => '-');
    p_rsp_val.more <= '-';
    s_start <= '0';
    
    case r.state is
      when STATE_RESET | STATE_WAIT =>
        null;

      when STATE_DADDR_GET | STATE_DATA_GET =>
        p_cmd_ack.ack <= '1';

      when STATE_EXECUTE =>
        s_start <= '1';

      when STATE_ACK_PUT =>
        p_rsp_val.val <= '1';
        p_rsp_val.data <= "0000000" & r.ack;
        p_rsp_val.more <= r.more;
    end case;
  end process;
  
end;
