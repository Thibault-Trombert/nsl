library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_data.bytestream.byte;
use nsl_data.bytestream.byte_string;
use nsl_data.bytestream.null_byte_string;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_logic.bool.all;

package device is

  component bus_interface_utmi8 is
    generic (
      hs_supported_c      : boolean     := false;
      self_powered_c      : boolean     := false;
      device_descriptor_c : byte_string;
      device_qualifier_c  : byte_string := null_byte_string;
      fs_config_1_c       : byte_string;
      hs_config_1_c       : byte_string := null_byte_string;
      string_1_c          : string      := "";
      string_2_c          : string      := "";
      string_3_c          : string      := "";
      string_4_c          : string      := "";
      string_5_c          : string      := "";
      string_6_c          : string      := "";
      string_7_c          : string      := "";
      string_8_c          : string      := "";
      string_9_c          : string      := "";

      phy_clock_rate_c : integer := 60000000;
      in_ep_count_c  : endpoint_idx_t := 0;
      out_ep_count_c : endpoint_idx_t := 0
      );
    port (
      reset_n_i     : in  std_ulogic;
      app_reset_n_o : out std_ulogic;
      hs_o          : out std_ulogic;
      suspend_o     : out std_ulogic;
      online_o      : out std_ulogic;

      phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
      phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie;
      phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
      phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;

      transfer_cmd_tap_o : out transfer_cmd;
      transfer_rsp_tap_o : out transfer_rsp;

      transfer_out_o : out transfer_cmd_vector(1 to out_ep_count_c);
      transfer_out_i : in  transfer_rsp_vector(1 to out_ep_count_c);
      transfer_in_o : out transfer_cmd_vector(1 to in_ep_count_c);
      transfer_in_i : in  transfer_rsp_vector(1 to in_ep_count_c)
      );
  end component;

  component bus_interface_ulpi8 is
    generic (
      hs_supported_c      : boolean     := false;
      self_powered_c      : boolean     := false;
      device_descriptor_c : byte_string;
      device_qualifier_c  : byte_string := null_byte_string;
      fs_config_1_c       : byte_string;
      hs_config_1_c       : byte_string := null_byte_string;
      string_1_c          : string      := "";
      string_2_c          : string      := "";
      string_3_c          : string      := "";
      string_4_c          : string      := "";
      string_5_c          : string      := "";
      string_6_c          : string      := "";
      string_7_c          : string      := "";
      string_8_c          : string      := "";
      string_9_c          : string      := "";

      phy_clock_rate_c : integer := 60000000;
      in_ep_count_c  : endpoint_idx_t := 0;
      out_ep_count_c : endpoint_idx_t := 0
      );
    port (
      reset_n_i     : in  std_ulogic;
      app_reset_n_o : out std_ulogic;
      hs_o          : out std_ulogic;
      suspend_o     : out std_ulogic;
      online_o      : out std_ulogic;

      phy_o : out nsl_usb.ulpi.ulpi8_link2phy;
      phy_i : in  nsl_usb.ulpi.ulpi8_phy2link;

      transfer_cmd_tap_o : out transfer_cmd;
      transfer_rsp_tap_o : out transfer_rsp;

      transfer_out_o : out transfer_cmd_vector(1 to out_ep_count_c);
      transfer_out_i : in  transfer_rsp_vector(1 to out_ep_count_c);
      transfer_in_o : out transfer_cmd_vector(1 to in_ep_count_c);
      transfer_in_i : in  transfer_rsp_vector(1 to in_ep_count_c)
      );
  end component;

  component device_ep_bulk_out is
    generic (
      hs_supported_c      : boolean;
      fs_mps_l2_c : integer range 3 to 6 := 6;
      mps_count_l2_c : integer := 1
      );
    port (
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      transfer_i : in  transfer_cmd;
      transfer_o : out transfer_rsp;

      valid_o     : out std_ulogic;
      data_o      : out byte;
      ready_i     : in  std_ulogic;
      available_o : out unsigned(if_else(hs_supported_c, 9, fs_mps_l2_c) + mps_count_l2_c downto 0)
      );
  end component;

  component device_ep_bulk_in is
    generic (
      hs_supported_c      : boolean;
      fs_mps_l2_c : integer range 3 to 6 := 6;
      mps_count_l2_c : integer := 1
      );
    port (
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      transfer_i : in  transfer_cmd;
      transfer_o : out transfer_rsp;

      valid_i : in  std_ulogic;
      data_i  : in  byte;
      ready_o : out std_ulogic;
      room_o  : out unsigned(if_else(hs_supported_c, 9, fs_mps_l2_c) + mps_count_l2_c downto 0);

      flush_i : in std_ulogic := '0'
      );
  end component;

  component device_ep_intr_in is
    port (
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      transfer_i : in  transfer_cmd;
      transfer_o : out transfer_rsp;

      valid_i   : in  std_ulogic;
      ready_o   : out std_ulogic;
      data_i    : in  byte_string;
      pending_o : out std_ulogic
      );
  end component;

  component device_ep_in_noop is
    port (
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      transfer_i : in  transfer_cmd;
      transfer_o : out transfer_rsp
      );
  end component;

end package;
