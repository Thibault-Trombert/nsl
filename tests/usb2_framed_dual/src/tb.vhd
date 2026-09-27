library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_usb, nsl_data;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use nsl_data.text.all;
use nsl_usb.usb.all;
use nsl_usb.descriptor.all;
use nsl_data.bytestream.all;
use nsl_usb.testing.all;

entity tb is
end tb;

architecture sim of tb is

  signal rst_neg_ext   : std_logic;

  signal p2s: utmi8_p2s;
  signal s2p: utmi8_s2p;

  function byte_range(left, right: byte) return byte_string
  is
    variable ret : byte_string(to_integer(unsigned(left)) to to_integer(unsigned(right)));
  begin
    for i in ret'range
    loop
      ret(i) := byte(to_unsigned(i, 8));
    end loop;
    return ret;
  end function;

begin

  usb_hs_slave : entity work.dut
  port map(
    reset_n_i       => rst_neg_ext,

    utmi_data_o => s2p.data,
    utmi_data_i => p2s.data,
    utmi_system_o => s2p.system,
    utmi_system_i => p2s.system
  );

  stim: process
  begin
    utmi_init(s2p, p2s);
    utmi_reset(s2p, p2s);
    utmi_hs_handshake(s2p, p2s);
    utmi_sof(s2p, p2s, x"123");
    utmi_wait(s2p, p2s, 1 us);

    utmi_control_write(s2p, p2s,
                       dev_addr => x"00",
                       request => REQUEST_SET_ADDRESS,
                       value => x"24");

    log_info("Configuration: two vendor interfaces, endpoints 1 and 2");
    utmi_control_read(s2p, p2s,
                      dev_addr => x"24",
                      request => REQUEST_GET_DESCRIPTOR,
                      length => x"200",
                      value => unsigned(DESCRIPTOR_TYPE_CONFIGURATION) & x"00",
                      data => "09023700020100804b"
                      & "0904000002ffffff00" & "07058102000200" & "07050102000200"
                      & "0904010002ffffff00" & "07058202000200" & "07050202000200",
                      mps => 64);

    utmi_control_write(s2p, p2s,
                       dev_addr => x"24",
                       request => REQUEST_SET_CONFIGURATION,
                       value => x"1");

    log_info("Interleaved traffic, each interface keeps its own");
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '0',
                      hex_data => to_hex_string(byte_range(x"00", x"3f")),
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"2",
                      toggle => '0',
                      hex_data => "a5b6c7",
                      handshake_pid => PID_ACK);
    utmi_transfer_out(s2p, p2s,
                      dev_addr => x"24",
                      ep_no => x"1",
                      toggle => '1',
                      hex_data => "4041",
                      handshake_pid => PID_ACK);
    utmi_wait(s2p, p2s, 1 us);

    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"2",
                     toggle => '0',
                     hex_data => "a5b6c7",
                     handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '0',
                     hex_data => to_hex_string(byte_range(x"00", x"3f")),
                     handshake_pid => PID_ACK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     toggle => '1',
                     hex_data => "4041",
                     handshake_pid => PID_ACK);

    log_info("Nothing left on either");
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"2",
                     error_pid => PID_NAK);
    utmi_transfer_in(s2p, p2s,
                     dev_addr => x"24",
                     ep_no => x"1",
                     error_pid => PID_NAK);

    terminate(0);
  end process;

end sim;
