library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_math, nsl_usb;
use nsl_data.bytestream.all;
use nsl_usb.usb.all;

package descriptor is

  -- USB 2.0 descriptor types (Table 9-5)
  constant TYPE_DEVICE                : integer := 1;
  constant TYPE_CONFIGURATION         : integer := 2;
  constant TYPE_STRING                : integer := 3;
  constant TYPE_INTERFACE             : integer := 4;
  constant TYPE_ENDPOINT              : integer := 5;
  constant TYPE_DEVICE_QUALIFIER      : integer := 6;
  constant TYPE_OTHER_SPEED_CONFIG    : integer := 7;
  constant TYPE_INTERFACE_POWER       : integer := 8;
  constant TYPE_OTG                   : integer := 9;
  constant TYPE_DEBUG                 : integer := 10;
  constant TYPE_INTERFACE_ASSOCIATION : integer := 11;
  constant TYPE_CDC_CS_INTERFACE      : integer := 16#24#;
  constant TYPE_CDC_CS_ENDPOINT       : integer := 16#25#;

  -- USB 3.0 descriptor types (Table 9-5)
  constant TYPE_BOS                   : integer := 15;     -- 0x0F
  constant TYPE_DEVICE_CAPABILITY     : integer := 16;     -- 0x10
  constant TYPE_SS_ENDPOINT_COMPANION : integer := 16#30#; -- 48

  -- Device Capability subtypes (Table 9-11)
  constant DEV_CAP_USB2_EXTENSION     : integer := 2;  -- 0x02
  constant DEV_CAP_SUPERSPEED_USB     : integer := 3;  -- 0x03
  constant DEV_CAP_CONTAINER_ID       : integer := 4;  -- 0x04

  constant SUBTYPE_CDC_FUNC_HEADER          : integer := 16#00#;
  constant SUBTYPE_CDC_FUNC_CALL_MGMT       : integer := 16#01#;
  constant SUBTYPE_CDC_FUNC_ACM             : integer := 16#02#;
  constant SUBTYPE_CDC_FUNC_ECM             : integer := 16#0F#;
  constant SUBTYPE_CDC_FUNC_DLM             : integer := 16#03#;
  constant SUBTYPE_CDC_FUNC_TEL_RING        : integer := 16#04#;
  constant SUBTYPE_CDC_FUNC_TEL_CALL        : integer := 16#05#;
  constant SUBTYPE_CDC_FUNC_UNION           : integer := 16#06#;
  constant SUBTYPE_CDC_FUNC_COUNTRY_SEL     : integer := 16#07#;
  constant SUBTYPE_CDC_FUNC_TEL_OP_MODE     : integer := 16#08#;
  constant SUBTYPE_CDC_FUNC_USB_TERM        : integer := 16#09#;
  constant SUBTYPE_CDC_FUNC_NETWORK         : integer := 16#0a#;
  constant SUBTYPE_CDC_FUNC_PROTOCOL_UNIT   : integer := 16#0b#;
  constant SUBTYPE_CDC_FUNC_EXTENSION_UNIT  : integer := 16#0c#;
  constant SUBTYPE_CDC_FUNC_CHANNEL_MGMT    : integer := 16#0d#;
  constant SUBTYPE_CDC_FUNC_CAPI            : integer := 16#0e#;
  constant SUBTYPE_CDC_FUNC_ETHERNET        : integer := 16#0f#;
  constant SUBTYPE_CDC_FUNC_ATM             : integer := 16#10#;

  constant EP_TTYPE_CONTROL   : unsigned(1 downto 0) := "00";
  constant EP_TTYPE_ISOCH     : unsigned(1 downto 0) := "01";
  constant EP_TTYPE_BULK      : unsigned(1 downto 0) := "10";
  constant EP_TTYPE_INTERRUPT : unsigned(1 downto 0) := "11";

  -- USB 2.0 device descriptor (Table 9-8).
  -- bcdUSB: 0x0110 (hs_support=false) or 0x0200 (hs_support=true).
  -- mps: bMaxPacketSize0 in bytes (8/16/32/64 for FS; 64 for HS).
  function device(
    hs_support : boolean;
    class, subclass, protocol : natural := 0;
    mps : natural;
    vendor_id, product_id, device_version : unsigned(15 downto 0);
    manufacturer_str_index, product_str_index, serial_str_index : natural := 0;
    config_count : natural := 1)
    return byte_string;

  -- USB 3.0 device descriptor (Table 9-8).
  -- bcdUSB=0x0300. bMaxPacketSize0=9 (exponent: 2^9=512 bytes, the only valid
  -- value for SuperSpeed per spec §9.6.1).
  function ss_device(
    class, subclass, protocol : natural := 0;
    vendor_id, product_id, device_version : unsigned(15 downto 0);
    manufacturer_str_index, product_str_index, serial_str_index : natural := 0;
    config_count : natural := 1)
    return byte_string;

  function endpoint(
    direction : direction_t;
    number : natural;
    ttype : unsigned(1 downto 0);
    mps : natural;
    interval : natural := 0)
    return byte_string;

  -- SuperSpeed Endpoint Companion descriptor (Table 9-20, type 0x30, bLength=6).
  -- Shall immediately follow the endpoint descriptor it applies to.
  -- max_burst: bMaxBurst 0..15 (0=1 packet per burst; 15=16 packets per burst).
  --            For control endpoints, shall be 0.
  -- attributes: bmAttributes, interpretation depends on endpoint type:
  --   Bulk:        bits 4:0 = MaxStreams (0=no streams; 1..16 -> 2^N streams)
  --   Isochronous: bits 1:0 = Mult (max pkts/interval = bMaxBurst x (Mult+1), max Mult=2)
  --   Control/Interrupt: shall be 0
  -- bytes_per_interval: wBytesPerInterval (LE 16-bit).
  --   Isochronous: total bytes per 125us service interval (must equal
  --                bMaxBurst x (Mult+1) x wMaxPacketSize of the endpoint).
  --   Interrupt (periodic): total bytes per service interval.
  --   Bulk/Control: shall be 0.
  function ss_endpoint_companion(
    max_burst          : natural := 0;
    attributes         : natural := 0;
    bytes_per_interval : natural := 0)
    return byte_string;

  -- Configuration descriptor (Table 9-15, bLength=9).
  -- ss=false (default): bMaxPower in 2-mA units, clamped to 500 mA.
  -- ss=true:            bMaxPower in 8-mA units, clamped to 900 mA.
  -- For SS configs, interface* blobs should include ss_endpoint_companion after
  -- each endpoint. wTotalLength is computed from the concatenated blobs.
  function config(
    config_no : natural;
    str_index : natural := 0;
    self_powered, remote_wakeup : boolean := false;
    max_power : natural;
    ss : boolean := false;
    interface0 : byte_string;
    interface1, interface2, interface3, other_desc : byte_string := null_byte_string)
    return byte_string;

  -- USB 3.0 full SS descriptor set: BOS descriptor & SS configuration, concatenated.
  --
  -- BOS is always built with capability_usb2_extension(lpm_capable=>true) —
  -- spec §9.6.2.1 "SuperSpeed devices shall set this bit to one" — plus a
  -- SuperSpeed Device Capability descriptor.  That USB 2.0 Extension capability
  -- IS the "backward USB 2.0 part": it advertises LPM support when the host
  -- enumerates the device at High Speed.
  --
  -- speeds_supported defaults to 12 (bit2=HS + bit3=5 Gbps), meaning the device
  -- is backward-compatible with USB 2.0 HS.  Set to 8 for SS-only devices.
  -- functionality_support=3 (SS) means all device functionality requires SS.
  -- bMaxPower is in 8 mA units, clamped to 900 mA (spec §9.6.3 SS config rule).
  -- interface* blobs shall include ss_endpoint_companion after every endpoint.
  --
  -- Returns bos_bytes & ss_config_bytes concatenated.  The BOS wTotalLength
  -- field (bytes 3:2 of the result) gives the split point if the caller needs
  -- to separate the two descriptors.
  function config_ss(
    config_no             : natural;
    str_index             : natural := 0;
    self_powered,
    remote_wakeup         : boolean := false;
    max_power             : natural;
    ltm_capable           : boolean := false;
    speeds_supported      : natural := 12;
    functionality_support : natural := 3;
    u1_exit_lat           : natural := 0;
    u2_exit_lat           : natural := 0;
    interface0            : byte_string;
    interface1, interface2,
    interface3, other_desc : byte_string := null_byte_string)
    return byte_string;

  function device_qualifier(
    usb_version : natural;
    class, subclass, protocol : natural := 0;
    mps0 : natural;
    config_count : natural := 1)
    return byte_string;

  function interface(
    interface_number : natural;
    alt_setting : natural := 0;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0;
    endpoint0, endpoint1, endpoint2, endpoint3, functional_desc : byte_string := null_byte_string)
    return byte_string;

  function interface_association(
    first_interface, interface_count : natural;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0)
    return byte_string;

  -- BOS descriptor (Table 9-9, bLength=5).
  -- Builds the 5-byte BOS header followed by cap0..cap3.
  -- wTotalLength = 5 + sum of all cap lengths.
  -- bNumDeviceCaps = count of non-empty caps.
  -- cap0 is required; cap1..cap3 default to empty.
  -- A SuperSpeed device shall include at minimum:
  --   cap0 => capability_usb2_extension(...)
  --   cap1 => capability_superspeed(...)
  function bos(
    cap0 : byte_string;
    cap1, cap2, cap3 : byte_string := null_byte_string)
    return byte_string;

  -- USB 2.0 Extension Capability descriptor (Table 9-12, bLength=7).
  -- bDevCapabilityType=0x02. bmAttributes is a LE 32-bit field:
  --   bit 0: Reserved, shall be 0.
  --   bit 1: LPM. "SuperSpeed devices shall set this bit to one" (spec §9.6.2.1).
  --   bits 31:2: Reserved, shall be 0.
  function capability_usb2_extension(
    lpm_capable : boolean := true)
    return byte_string;

  -- SuperSpeed USB Device Capability descriptor (Table 9-13, bLength=10).
  -- bDevCapabilityType=0x03. Required for all SuperSpeed devices.
  -- ltm_capable:           bmAttributes bit 1 - device supports LTM.
  -- speeds_supported:      wSpeedsSupported LE16 bitmap:
  --                          bit 0 = Low Speed, bit 1 = Full Speed,
  --                          bit 2 = High Speed, bit 3 = 5 Gbps (SS).
  -- functionality_support: bFunctionalitySupport - lowest speed at which all
  --                          device functionality is available (1=FS, 2=HS, 3=SS).
  --                          Valid values are a subset of wSpeedsSupported bits.
  -- u1_exit_lat:           bU1DevExitLat - U1 device exit latency.
  --                          0x00=zero; 0x01..0x0A = less than N us; 0x0B..0xFF reserved.
  -- u2_exit_lat:           wU2DevExitLat - U2 device exit latency (LE16).
  --                          0x0000=zero; 0x0001..0x07FF = less than N us; 0x0800+ reserved.
  function capability_superspeed(
    ltm_capable           : boolean := false;
    speeds_supported      : natural := 8;
    functionality_support : natural := 1;
    u1_exit_lat           : natural := 0;
    u2_exit_lat           : natural := 0)
    return byte_string;

  -- Container ID Capability descriptor (Table 9-14, bLength=20).
  -- bDevCapabilityType=0x04. Mandatory for USB 3.0 hubs; optional for others.
  -- container_id must be exactly 16 bytes (128-bit UUID per IETF RFC 4122).
  function capability_container_id(
    container_id : byte_string)
    return byte_string;

  function cdc_functional_header(
    cdc_version : natural := 16#0120#)
    return byte_string;

  function cdc_functional_acm(
    capabilities : natural := 0)
    return byte_string;

  function cdc_functional_union(
    control, sub0 : natural)
    return byte_string;

  function cdc_functional_call_management(
    capabilities, data_interface : natural)
    return byte_string;

  function cdc_functional_ecm(
    iMacAddress, max_segment_size, statistics,
    nbr_mc_filters, nbr_power_filters : natural := 0)
    return byte_string;

  function language(
    langid : natural := 16#409#)
    return byte_string;

  function string_from_ascii(
    str : string)
    return byte_string;

  function string_descriptor_length(s: in string)
    return natural;

end package;

package body descriptor is

  use nsl_data.endian.all;
  use nsl_logic.bool.all;

  function bv(n: unsigned)
    return byte_string
  is
    variable ret : byte_string(1 to 1);
  begin
    assert n'length <= 8 severity failure;
    ret(1) := byte(resize(n, 8));
    return ret;
  end function;

  function bv(n: integer range 0 to 255)
    return byte_string
  is
    variable ret : byte_string(1 to 1);
  begin
    ret(1) := byte(to_unsigned(n, 8));
    return ret;
  end function;

  function wv(n: unsigned)
    return byte_string
  is
  begin
    assert n'length <= 16 severity failure;
    return to_le(resize(n, 16));
  end function;

  function wv(n: integer range 0 to 65535)
    return byte_string
  is
  begin
    return wv(to_unsigned(n, 16));
  end function;

  function wwv(n: unsigned)
    return byte_string
  is
  begin
    assert n'length <= 32 severity failure;
    return to_le(resize(n, 32));
  end function;

  function wwv(n: integer range 0 to 65535)
    return byte_string
  is
  begin
    return wwv(to_unsigned(n, 32));
  end function;

  function sized(
    dtype : integer range 0 to 255;
    desc : byte_string)
    return byte_string
  is
  begin
    return bv(integer(desc'length+2)) & bv(dtype) & desc;
  end function;

  function device(
    hs_support : boolean;
    class, subclass, protocol : natural := 0;
    mps : natural;
    vendor_id, product_id, device_version : unsigned(15 downto 0);
    manufacturer_str_index, product_str_index, serial_str_index : natural := 0;
    config_count : natural := 1)
    return byte_string
  is
  begin
    return sized(
      TYPE_DEVICE,
      wv(if_else(hs_support, 16#0200#, 16#0110#))
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(mps)
      & wv(vendor_id)
      & wv(product_id)
      & wv(device_version)
      & bv(manufacturer_str_index)
      & bv(product_str_index)
      & bv(serial_str_index)
      & bv(config_count)
      );
  end device;

  -- Table 9-8: bcdUSB=0x0300, bMaxPacketSize0=9 (only valid SS value, §9.6.1)
  function ss_device(
    class, subclass, protocol : natural := 0;
    vendor_id, product_id, device_version : unsigned(15 downto 0);
    manufacturer_str_index, product_str_index, serial_str_index : natural := 0;
    config_count : natural := 1)
    return byte_string
  is 
  begin
    return sized(
      TYPE_DEVICE,
      wv(16#0320#)
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(9)
      & wv(vendor_id)
      & wv(product_id)
      & wv(device_version)
      & bv(manufacturer_str_index)
      & bv(product_str_index)
      & bv(serial_str_index)
      & bv(config_count)
      );
  end ss_device;

  function endpoint(
    direction : direction_t;
    number : natural;
    ttype : unsigned(1 downto 0);
    mps : natural;
    interval : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_ENDPOINT,
      bv(if_else(direction = DEVICE_TO_HOST, 16#80#, 0) + number)
      & bv(ttype)
      & wv(mps)
      & bv(interval)
      );
  end endpoint;

  -- Table 9-20: bLength=6 (sized adds 2 to 4-byte desc).
  function ss_endpoint_companion(
    max_burst          : natural := 0;
    attributes         : natural := 0;
    bytes_per_interval : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_SS_ENDPOINT_COMPANION,
      bv(max_burst)
      & bv(attributes)
      & wv(bytes_per_interval)
      );
  end ss_endpoint_companion;

  -- Table 9-15: bMaxPower units differ: 2 mA/unit for FS/HS, 8 mA/unit for SS.
  function config(
    config_no : natural;
    str_index : natural := 0;
    self_powered, remote_wakeup : boolean := false;
    max_power : natural;
    ss : boolean := false;
    interface0 : byte_string;
    interface1, interface2, interface3, other_desc : byte_string := null_byte_string)
    return byte_string
  is
    variable attrs           : byte;
    variable interface_count : natural := 1;
    variable bmax_power      : natural;
  begin
    if interface1'length /= 0 then
      interface_count := interface_count + 1;
    end if;
    if interface2'length /= 0 then
      interface_count := interface_count + 1;
    end if;
    if interface3'length /= 0 then
      interface_count := interface_count + 1;
    end if;

    attrs    := x"80";
    attrs(6) := to_logic(self_powered);
    attrs(5) := to_logic(remote_wakeup);

    if ss then
      bmax_power := nsl_math.arith.min(max_power, 900) / 8;
    else
      bmax_power := nsl_math.arith.min(max_power, 500) / 2;
    end if;

    return sized(
      TYPE_CONFIGURATION,
      wv(interface0'length + interface1'length
         + interface2'length + interface3'length
         + other_desc'length + 9)
      & bv(interface_count)
      & bv(config_no)
      & bv(str_index)
      & attrs
      & bv(bmax_power)
      ) & other_desc & interface0 & interface1 & interface2 & interface3;
  end config;

  function config_ss(
    config_no             : natural;
    str_index             : natural := 0;
    self_powered,
    remote_wakeup         : boolean := false;
    max_power             : natural;
    ltm_capable           : boolean := false;
    speeds_supported      : natural := 12;
    functionality_support : natural := 3;
    u1_exit_lat           : natural := 0;
    u2_exit_lat           : natural := 0;
    interface0            : byte_string;
    interface1, interface2,
    interface3, other_desc : byte_string := null_byte_string)
    return byte_string
  is
  begin
    return bos(
               cap0 => capability_usb2_extension(lpm_capable => true),
               cap1 => capability_superspeed(
                   ltm_capable           => ltm_capable,
                   speeds_supported      => speeds_supported,
                   functionality_support => functionality_support,
                   u1_exit_lat           => u1_exit_lat,
                   u2_exit_lat           => u2_exit_lat))
           & config(
               config_no     => config_no,
               str_index     => str_index,
               self_powered  => self_powered,
               remote_wakeup => remote_wakeup,
               max_power     => max_power,
               ss            => true,
               interface0    => interface0,
               interface1    => interface1,
               interface2    => interface2,
               interface3    => interface3,
               other_desc    => other_desc);
  end config_ss;

  function interface(
    interface_number : natural;
    alt_setting : natural := 0;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0;
    endpoint0, endpoint1, endpoint2, endpoint3, functional_desc : byte_string := null_byte_string)
    return byte_string
  is
    variable endpoint_count : natural := 0;
  begin
    if endpoint0'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;
    if endpoint1'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;
    if endpoint2'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;
    if endpoint3'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;

    return sized(
      TYPE_INTERFACE,
      bv(interface_number)
      & bv(alt_setting)
      & bv(endpoint_count)
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(str_index)
      ) & functional_desc & endpoint0 & endpoint1 & endpoint2 & endpoint3;
  end interface;

  -- Table 9-9: BOS header is 5 bytes (not using sized() because the header has
  -- wTotalLength and bNumDeviceCaps in addition to the standard bLength/bType).
  function bos(
    cap0 : byte_string;
    cap1, cap2, cap3 : byte_string := null_byte_string)
    return byte_string
  is
    variable num_caps         : natural := 1;
    variable total_cap_length : natural;
  begin
    if cap1'length /= 0 then num_caps := num_caps + 1; end if;
    if cap2'length /= 0 then num_caps := num_caps + 1; end if;
    if cap3'length /= 0 then num_caps := num_caps + 1; end if;
    total_cap_length := cap0'length + cap1'length + cap2'length + cap3'length;
    return bv(5)
        & bv(TYPE_BOS)
        & wv(5 + total_cap_length)
        & bv(num_caps)
        & cap0 & cap1 & cap2 & cap3;
  end bos;

  -- Table 9-12: bLength=7 (sized adds 2 to 5-byte desc). bmAttributes LE32:
  -- bit0=reserved/0, bit1=LPM, bits31:2=reserved/0.
  -- "SuperSpeed devices shall set this bit to one" (§9.6.2.1).
  function capability_usb2_extension(
    lpm_capable : boolean := true)
    return byte_string
  is
    variable attrs : unsigned(31 downto 0) := (others => '0');
  begin
    if lpm_capable then
      attrs(1) := '1';
    end if;
    return sized(
      TYPE_DEVICE_CAPABILITY,
      bv(DEV_CAP_USB2_EXTENSION)
      & wwv(attrs)
      );
  end capability_usb2_extension;

  -- Table 9-13: bLength=10 (sized adds 2 to 8-byte desc).
  function capability_superspeed(
    ltm_capable           : boolean := false;
    speeds_supported      : natural := 8;
    functionality_support : natural := 1;
    u1_exit_lat           : natural := 0;
    u2_exit_lat           : natural := 0)
    return byte_string
  is
    variable bm_attrs : byte := x"00";
  begin
    if ltm_capable then
      bm_attrs(1) := '1';
    end if;
    return sized(
      TYPE_DEVICE_CAPABILITY,
      bv(DEV_CAP_SUPERSPEED_USB)
      & bm_attrs
      & wv(speeds_supported)
      & bv(functionality_support)
      & bv(u1_exit_lat)
      & wv(u2_exit_lat)
      );
  end capability_superspeed;

  -- Table 9-14: bLength=20 (sized adds 2 to 18-byte desc).
  -- container_id must be exactly 16 bytes (128-bit UUID per RFC 4122).
  function capability_container_id(
    container_id : byte_string)
    return byte_string
  is
  begin
    assert container_id'length = 16 severity failure;
    return sized(
      TYPE_DEVICE_CAPABILITY,
      bv(DEV_CAP_CONTAINER_ID)
      & bv(0)
      & container_id
      );
  end capability_container_id;

  function cdc_functional_header(
    cdc_version : natural := 16#0120#)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_HEADER)
      & wv(cdc_version));
  end function cdc_functional_header;

  function cdc_functional_acm(
    capabilities : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_ACM)
      & bv(capabilities));
  end function cdc_functional_acm;

  function cdc_functional_union(
    control, sub0 : natural)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_UNION)
      & bv(control)
      & bv(sub0));
  end function cdc_functional_union;

  function cdc_functional_call_management(
    capabilities, data_interface : natural)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_CALL_MGMT)
      & bv(capabilities)
      & bv(data_interface));
  end function cdc_functional_call_management;

  function language(
    langid : natural := 16#409#)
    return byte_string
  is
  begin
    return sized(
      TYPE_STRING,
      wv(langid));
  end function language;

  function cdc_functional_ecm(
    iMacAddress, max_segment_size, statistics,
    nbr_mc_filters, nbr_power_filters : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_ECM)
      & bv(iMacAddress)
      & wwv(statistics)
      & wv(max_segment_size)
      & wv(nbr_mc_filters)
      & bv(nbr_power_filters));
  end function cdc_functional_ecm;

  function string_from_ascii(
    str : string)
    return byte_string
  is
    alias sstr: string(1 to str'length) is str;
    variable utf16: byte_string(1 to str'length*2);
  begin
    if sstr'length = 0 then
      return null_byte_string;
    end if;
    for i in sstr'range loop
      utf16(i*2-1 to i*2) := wv(character'pos(sstr(i)));
    end loop;
    return sized(TYPE_STRING, utf16);
  end function string_from_ascii;

  function string_descriptor_length(s: in string)
    return natural is
  begin
    assert s'length <= 126;
    if s'length = 0 then
      return 0;
    else
      return 2 + 2 * s'length;
    end if;
  end function;

  function device_qualifier(
    usb_version : natural;
    class, subclass, protocol : natural := 0;
    mps0 : natural;
    config_count : natural := 1)
    return byte_string
  is
  begin
    return sized(
      TYPE_DEVICE_QUALIFIER,
      wv(usb_version)
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(mps0)
      & bv(config_count)
      & bv(0)
      );
  end function device_qualifier;

  function interface_association(
    first_interface, interface_count : natural;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_INTERFACE_ASSOCIATION,
      bv(first_interface)
      & bv(interface_count)
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(str_index));
  end function interface_association;

end package body;
