library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking;

entity i2s_transmitter is
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_i : in  std_ulogic;
    ws_i  : in  std_ulogic;
    sd_o  : out std_ulogic;

    ready_o   : out std_ulogic;
    channel_o : out std_ulogic;
    data_i  : in unsigned
    );
end entity;

architecture beh of i2s_transmitter is

  type regs_t is
  record
    sck, ws, sd : std_ulogic;
    shreg : unsigned(data_i'range);
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.shreg <= (others => '0');
    end if;
  end process;

  transition: process(r, ws_i, sck_i, data_i) is
  begin
    rin <= r;

    rin.sck <= sck_i;

    if r.sck = '1' and sck_i = '0' then
      rin.sd <= r.shreg(r.shreg'left);
    end if;

    if r.sck = '0' and sck_i = '1' then
      rin.ws <= ws_i;
    
      if r.ws /= ws_i then
        rin.shreg <= data_i;
      else
        rin.shreg <= r.shreg(r.shreg'left-1 downto r.shreg'right) & "0";
      end if;
    end if;
  end process;

  mealy: process(r, ws_i, sck_i) is
  begin
    ready_o <= '0';
    channel_o <= '-';

    if r.ws /= ws_i and r.sck = '0' and sck_i = '1' then
      ready_o <= '1';
      channel_o <= not r.ws;
    end if;
  end process;

  sd_o <= r.sd;
  
end architecture;

