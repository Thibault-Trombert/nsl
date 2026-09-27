library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_logic, nsl_math, nsl_data, nsl_clocking, nsl_bnoc;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.device.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_usb.descriptor.all;

entity vendor_framed_pair_dual is
  generic (
    vendor_id_c            : unsigned(15 downto 0);
    product_id_c           : unsigned(15 downto 0);
    device_version_c       : unsigned(15 downto 0);
    manufacturer_c         : string                := "";
    product_c              : string                := "";
    serial_c               : string                := "";
    hs_supported_c         : boolean               := false;
    self_powered_c         : boolean               := false;
    phy_clock_rate_c : integer := 60000000;
    framed_fs_mps_l2_c : integer range 3 to 6 := 6;
    framed_double_buffer_c : boolean := true;
    serial_i_length_c : natural := 0
    );
  port (
    reset_n_i     : in  std_ulogic;
    app_reset_n_o : out std_ulogic;
    hs_o        : out std_ulogic;
    suspend_o   : out std_ulogic;
    online_o    : out std_ulogic;
    serial_i    : in string(1 to serial_i_length_c) := (others => nul);

    out0_o     : out nsl_bnoc.framed.framed_req;
    out0_i     : in  nsl_bnoc.framed.framed_ack;
    in0_i      : in  nsl_bnoc.framed.framed_req;
    in0_o      : out nsl_bnoc.framed.framed_ack;

    out1_o     : out nsl_bnoc.framed.framed_req;
    out1_i     : in  nsl_bnoc.framed.framed_ack;
    in1_i      : in  nsl_bnoc.framed.framed_req;
    in1_o      : out nsl_bnoc.framed.framed_ack;

    frame_number_o : out frame_no_t;
    frame_o        : out std_ulogic;
    microframe_o   : out std_ulogic;

    transaction_cmd_tap_o : out nsl_usb.sie.transaction_cmd;
    transaction_rsp_tap_o : out nsl_usb.sie.transaction_rsp;

    phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
    phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;
    phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
    phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie
    );
end entity vendor_framed_pair_dual;

architecture beh of vendor_framed_pair_dual is

  signal s_out : transaction_bus_vector(1 to 2);
  signal s_in : transaction_bus_vector(1 to 2);

  signal app_reset_n : std_ulogic;
  
  function if_string(c: string; no: natural)
    return natural is
  begin
    if c'length /= 0 then
      return no;
    else
      return 0;
    end if;
  end function;

  -- Interface i uses endpoint i+1, both directions.
  function do_config_descriptor(mps : integer)
    return byte_string
  is
  begin
    return nsl_usb.descriptor.config(
      config_no => 1,
      self_powered => self_powered_c,
      max_power => 150,

      interface0 => nsl_usb.descriptor.interface(
        interface_number => 0,
        alt_setting => 0,
        class => 16#ff#, subclass => 16#ff#, protocol => 16#ff#,
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => 1,
          ttype => EP_TTYPE_BULK,
          mps => mps),
        endpoint1 => nsl_usb.descriptor.endpoint(
          direction => HOST_TO_DEVICE,
          number => 1,
          ttype => EP_TTYPE_BULK,
          mps => mps)),

      interface1 => nsl_usb.descriptor.interface(
        interface_number => 1,
        alt_setting => 0,
        class => 16#ff#, subclass => 16#ff#, protocol => 16#ff#,
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => 2,
          ttype => EP_TTYPE_BULK,
          mps => mps),
        endpoint1 => nsl_usb.descriptor.endpoint(
          direction => HOST_TO_DEVICE,
          number => 2,
          ttype => EP_TTYPE_BULK,
          mps => mps)));

  end function;
  
begin

  bus_interface: nsl_usb.device.bus_interface_utmi8
    generic map (
      hs_supported_c => hs_supported_c,
      phy_clock_rate_c => phy_clock_rate_c,

      device_descriptor_c => nsl_usb.descriptor.device(
        hs_support => hs_supported_c,
        mps => 64,
        vendor_id => vendor_id_c,
        product_id => product_id_c,
        device_version => device_version_c,
        manufacturer_str_index => if_string(manufacturer_c, 1),
        product_str_index => if_string(product_c, 2),
        serial_str_index => if_else(serial_i'length /= 0, 10, if_string(serial_c, 3))),

      device_qualifier_c => nsl_usb.descriptor.device_qualifier(
        usb_version => 16#0200#,
        mps0 => 64),

      fs_config_1_c => do_config_descriptor(mps => 2 ** framed_fs_mps_l2_c),
      hs_config_1_c => do_config_descriptor(mps => 2 ** 9),

      string_1_c => manufacturer_c,
      string_2_c => product_c,
      string_3_c => serial_c,
      
      in_ep_count_c => s_in'length,
      out_ep_count_c => s_out'length,

      string_10_i_length_c => serial_i_length_c
      )
    port map(
      reset_n_i => reset_n_i,
      app_reset_n_o => app_reset_n,

      hs_o => hs_o,
      suspend_o => suspend_o,
      online_o => online_o,

      string_10_i => serial_i,

      phy_system_o => phy_system_o,
      phy_system_i => phy_system_i,
      phy_data_o => phy_data_o,
      phy_data_i => phy_data_i,

      frame_number_o => frame_number_o,
      frame_o => frame_o,
      microframe_o => microframe_o,
      
      transaction_cmd_tap_o => transaction_cmd_tap_o,
      transaction_rsp_tap_o => transaction_rsp_tap_o,

      transaction_out_o(1) => s_out(1).cmd,
      transaction_out_o(2) => s_out(2).cmd,
      transaction_out_i(1) => s_out(1).rsp,
      transaction_out_i(2) => s_out(2).rsp,
      transaction_in_o(1) => s_in(1).cmd,
      transaction_in_o(2) => s_in(2).cmd,
      transaction_in_i(1) => s_in(1).rsp,
      transaction_in_i(2) => s_in(2).rsp
      );

  framed_in0 : nsl_usb.device.device_ep_framed_in
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => framed_fs_mps_l2_c,
      double_buffer_c => framed_double_buffer_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in(1).cmd,
      transaction_o => s_in(1).rsp,

      framed_o => in0_o,
      framed_i => in0_i
      );

  framed_out0 : nsl_usb.device.device_ep_framed_out
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => framed_fs_mps_l2_c,
      double_buffer_c => framed_double_buffer_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_out(1).cmd,
      transaction_o => s_out(1).rsp,

      framed_o => out0_o,
      framed_i => out0_i
      );

  framed_in1 : nsl_usb.device.device_ep_framed_in
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => framed_fs_mps_l2_c,
      double_buffer_c => framed_double_buffer_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in(2).cmd,
      transaction_o => s_in(2).rsp,

      framed_o => in1_o,
      framed_i => in1_i
      );

  framed_out1 : nsl_usb.device.device_ep_framed_out
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => framed_fs_mps_l2_c,
      double_buffer_c => framed_double_buffer_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_out(2).cmd,
      transaction_o => s_out(2).rsp,

      framed_o => out1_o,
      framed_i => out1_i
      );

  app_reset_n_o <= app_reset_n;
  
end architecture;
