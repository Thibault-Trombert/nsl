library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_bnoc;
use nsl_usb.utmi.all;

entity dut is
  port(
    reset_n_i : in std_logic;

    utmi_data_o : out utmi_data8_sie2phy;
    utmi_data_i : in utmi_data8_phy2sie;
    utmi_system_o : out utmi_system_sie2phy;
    utmi_system_i : in utmi_system_phy2sie
    );
end entity;

architecture beh of dut is

  signal s_out, s_in : nsl_bnoc.framed.framed_bus_array(0 to 1);

  signal reset_n_sys : std_ulogic;
  signal clock_int, reset_n_int : std_ulogic;

  signal online : std_ulogic;

begin

  clk_gen: process
  begin
    while true
    loop
      clock_int <= '0';
      wait for 8333 ps;
      clock_int <= '1';
      wait for 8333 ps;
    end loop;
  end process;

  reset_gen: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_int,
      data_i => reset_n_i,
      data_o => reset_n_int
      );
 
  usb_device: nsl_usb.func.vendor_framed_pair_dual
    generic map(
      vendor_id_c => x"1234",
      product_id_c => x"5678",
      device_version_c => x"0100",
      manufacturer_c => "NSL",
      product_c => "Dual",
      hs_supported_c => true,
      self_powered_c => false,
      framed_fs_mps_l2_c => 6,
      framed_double_buffer_c => true
      )
    port map(
      reset_n_i => reset_n_int,
      app_reset_n_o => reset_n_sys,
      online_o => online,

      phy_system_o => utmi_system_o,
      phy_system_i => utmi_system_i,
      phy_data_o => utmi_data_o,
      phy_data_i => utmi_data_i,

      out0_o => s_out(0).req,
      out0_i => s_out(0).ack,
      in0_o => s_in(0).ack,
      in0_i => s_in(0).req,

      out1_o => s_out(1).req,
      out1_i => s_out(1).ack,
      in1_o => s_in(1).ack,
      in1_i => s_in(1).req
      );

  loopbacks: for i in 0 to 1
  generate
    loopback: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 16,
        clk_count => 1
        )
      port map(
        p_resetn => reset_n_sys,
        p_clk(0) => utmi_system_i.clock,

        p_out_val => s_in(i).req,
        p_out_ack => s_in(i).ack,
        p_in_val => s_out(i).req,
        p_in_ack => s_out(i).ack
        );
  end generate;

end architecture;
