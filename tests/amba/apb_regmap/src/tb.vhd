library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.apb.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal bus_s: bus_t;

  constant config_c : config_t := config(address_width => 32,
                                         data_bus_width => 32);

begin

  writer: process is
  begin
    done_s(0) <= '0';
    
    bus_s.m <= transfer_idle(config_c);

    wait for 30 ns;
    wait until falling_edge(clock_s);

    apb_write(config_c, clock_s, bus_s.s, bus_s.m, reg => 0, reg_lsb => 2, val => x"00010203");
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, reg => 1, reg_lsb => 2, val => x"04050607");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 0, reg_lsb => 2, val => x"00010203");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 2, reg_lsb => 2, val => x"04050607");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 18, reg_lsb => 2, val => x"04050607");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 15, reg_lsb => 2, val => x"deadbeef");

    -- Wait states: register 3 holds each write for three cycles,
    -- register 4 reads it back as long, register 5 counts the writes
    -- register 3 took, register 6 the cycles they were strobed.
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, reg => 3, reg_lsb => 2, val => x"11223344");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 4, reg_lsb => 2, val => x"11223344");
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, reg => 3, reg_lsb => 2, val => x"55667788");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 4, reg_lsb => 2, val => x"55667788");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 5, reg_lsb => 2, val => x"00000002");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 6, reg_lsb => 2, val => x"00000008");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 0, reg_lsb => 2, val => x"00010203");
    
    done_s(0) <= '1';
    wait;
  end process;

  regmap: block is
    signal reg_no_s: natural range 0 to 15;
    signal w_value_s, r_value_s : unsigned(31 downto 0);
    signal w_strobe_s, r_strobe_s, w_ready_s, r_valid_s : std_ulogic;
    signal held_s : natural range 0 to 3;
    signal reg3: unsigned(31 downto 0);
    signal reg3_writes, reg3_strobes, reg3_view: unsigned(31 downto 0);

    signal reg0: unsigned(31 downto 0);
    signal reg1: unsigned(31 downto 0);
  begin
    writing: process(clock_s, reset_n_s) is
    begin
      if rising_edge(clock_s) then
        if w_strobe_s = '1' and w_ready_s = '1' then
          case reg_no_s is
            when 0 =>
              reg0 <= w_value_s;

            when 1 =>
              reg1 <= w_value_s;

            when 3 =>
              reg3 <= w_value_s;
              reg3_writes <= reg3_writes + 1;

            when others =>
              null;
          end case;
        end if;

        if w_strobe_s = '1' and reg_no_s = 3 then
          reg3_strobes <= reg3_strobes + 1;
        end if;

        if (w_strobe_s = '1' and w_ready_s = '0')
          or (r_strobe_s = '1' and r_valid_s = '0') then
          held_s <= held_s + 1;
        else
          held_s <= 0;
        end if;
      end if;

      if reset_n_s = '0' then
        reg3_writes <= (others => '0');
        reg3_strobes <= (others => '0');
        held_s <= 0;
      end if;
    end process;

    w_ready_s <= '0' when reg_no_s = 3 and held_s /= 3 else '1';
    r_valid_s <= '0' when reg_no_s = 4 and held_s /= 3 else '1';
    reg3_view <= reg3 when held_s = 3 else x"badbad00";

    with reg_no_s select r_value_s <=
      reg0        when 0,
      x"ebadf00d" when 1,
      reg1        when 2,
      reg3_view   when 4,
      reg3_writes when 5,
      reg3_strobes when 6,
      x"deadbeef" when others;

    dut: nsl_amba.apb.apb_regmap
      generic map(
        config_c => config_c,
        reg_count_l2_c => 4
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        apb_i => bus_s.m,
        apb_o => bus_s.s,

        reg_no_o => reg_no_s,
        w_value_o => w_value_s,
        w_strobe_o => w_strobe_s,
        w_ready_i => w_ready_s,
        r_value_i => r_value_s,
        r_strobe_o => r_strobe_s,
        r_valid_i => r_valid_s
        );
  end block;  

  dumper: nsl_amba.apb.apb_dumper
    generic map(
      config_c => config_c,
      prefix_c => "RAM"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => bus_s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
