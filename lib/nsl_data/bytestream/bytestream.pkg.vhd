library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package bytestream is

  subtype byte_hex_string is string(1 to 2);
  subtype byte is std_ulogic_vector(7 downto 0);
  type byte_string is array(natural range <>) of byte;

  function from_suv(blob: std_ulogic_vector) return byte_string;
  function byte_from_hex(blob: byte_hex_string) return byte;
  function from_hex(blob: string) return byte_string;
  function to_byte(c : character) return byte;
  function to_byte(i : integer) return byte;
  function to_integer(b: byte) return integer;
  function to_character(b: byte) return character;
  function to_byte_string(s : string) return byte_string;

  function "="(l, r : byte_string) return boolean;
  function "/="(l, r : byte_string) return boolean;
  function "not"(v : byte_string) return byte_string;
  function "and"(l, r : byte_string) return byte_string;
  function "or"(l, r : byte_string) return byte_string;
  function "xor"(l, r : byte_string) return byte_string;

  constant null_byte_string : byte_string(1 to 0) := (others => x"00");
  constant dontcare_byte_c : byte := (others => '-');

  function shift_left(s: byte_string;
                      b: byte := dontcare_byte_c) return byte_string;
  function shift_right(s: byte_string;
                       b: byte := dontcare_byte_c) return byte_string;
  function first_left(s: byte_string) return byte;
  function first_right(s: byte_string) return byte;

  function rot_left(s: byte_string) return byte_string;
  function rot_right(s: byte_string) return byte_string;
  
  type byte_stream is access byte_string;
  procedure write(s: inout byte_stream; constant d: byte);
  procedure write(s: inout byte_stream; constant d: byte_string);
  procedure write(s: inout byte_stream; d: inout byte_stream);
  
end package bytestream;

package body bytestream is

  function from_suv(blob: std_ulogic_vector) return byte_string is
    alias xblob : std_ulogic_vector(0 to blob'length - 1) is blob;
    variable ret : byte_string(0 to blob'length / 8 -1);
  begin
    assert
      (blob'length mod 8) = 0
      report "blob vector should be a multiple of 8 bits"
      severity failure;

    for i in ret'range
    loop
      ret(i) := xblob(i * 8 to i * 8 + 7);
    end loop;

    return ret;
  end function;

  function nibble_to_suv(nibble : character) return std_ulogic_vector is
  begin
    case nibble is
      when '0' => return x"0";
      when '1' => return x"1";
      when '2' => return x"2";
      when '3' => return x"3";
      when '4' => return x"4";
      when '5' => return x"5";
      when '6' => return x"6";
      when '7' => return x"7";
      when '8' => return x"8";
      when '9' => return x"9";
      when 'a'|'A' => return x"a";
      when 'b'|'B' => return x"b";
      when 'c'|'C' => return x"c";
      when 'd'|'D' => return x"d";
      when 'e'|'E' => return x"e";
      when 'f'|'F' => return x"f";
      when others => return "XXXX";
    end case;
  end function;

  function byte_from_hex(blob: byte_hex_string) return byte is
  begin
    return nibble_to_suv(blob(1)) & nibble_to_suv(blob(2));
  end function;

  function from_hex(blob: string) return byte_string is
    alias xblob : string(1 to blob'length) is blob;
    variable ret : byte_string(0 to blob'length / 2 -1);
  begin
    assert
      (blob'length mod 2) = 0
      report "blob vector should contain an even count of characters"
      severity failure;

    for i in ret'range
    loop
      ret(i) := byte_from_hex(xblob(i * 2 + 1 to i * 2 + 2));
    end loop;

    return ret;
  end function;

  function "="(l, r : byte_string) return boolean is
    alias lv : byte_string(0 to l'length-1) is l;
    alias rv : byte_string(0 to r'length-1) is r;
    variable result : boolean;
  begin
    t: if l'length /= r'length THEN
      report "Vectors of differing sizes passed"
        severity warning;
      result := false;
    else
      result := true;
      fe: for i in lv'range loop
        result := result and (lv(i) = rv(i));
      end loop;
    end if;
    return result;
  end function;
    
  function "/="(l, r : byte_string) return boolean is
  begin
    return not (l = r);
  end function;

  function to_byte(i : integer) return byte
  is
  begin
    return byte(to_unsigned(i, 8));
  end function;

  function to_byte(c : character) return byte is
  begin
    return byte(to_unsigned(character'pos(c), 8));
  end function;

  function to_integer(b: byte) return integer is
  begin
    return to_integer(unsigned(b));
  end function;

  function to_character(b: byte) return character is
  begin
    return character'val(to_integer(b));
  end function;

  function to_byte_string(s : string) return byte_string is
    alias ss : string(1 to s'length) is s;
    variable ret : byte_string(1 to s'length);
  begin
    for i in ss'range
    loop
      ret(i) := to_byte(ss(i));
    end loop;
    return ret;
  end function;

  procedure write(s: inout byte_stream; constant d: byte)
  is
    variable n: byte_stream;
  begin
    n := new byte_string(0 to s.all'length);
    n.all := s.all & d;
    deallocate(s);
    s := n;
  end procedure;

  procedure write(s: inout byte_stream; constant d: byte_string)
  is
    variable n: byte_stream;
  begin
    n := new byte_string(0 to s.all'length + d'length - 1);
    n.all := s.all & d;
    deallocate(s);
    s := n;
  end procedure;

  procedure write(s: inout byte_stream; d: inout byte_stream)
  is
  begin
    write(s, d.all);
  end procedure;

  function shift_left(s: byte_string;
                      b: byte := dontcare_byte_c) return byte_string
  is
    alias xs: byte_string(0 to s'length-1) is s;
  begin
    if s'length = 0 then
      return null_byte_string;
    end if;
    return xs(1 to xs'right) & b;
  end function;

  function shift_right(s: byte_string;
                       b: byte := dontcare_byte_c) return byte_string
  is
    alias xs: byte_string(0 to s'length-1) is s;
  begin
    if s'length = 0 then
      return null_byte_string;
    end if;
    return b & xs(0 to xs'right-1);
  end function;

  function rot_left(s: byte_string) return byte_string
  is
  begin
    if s'length = 0 then
      return null_byte_string;
    end if;
    return shift_left(s, s(s'left));
  end function;
  
  function rot_right(s: byte_string) return byte_string
  is
  begin
    if s'length = 0 then
      return null_byte_string;
    end if;
    return shift_right(s, s(s'right));
  end function;

  function "not"(v : byte_string) return byte_string
  is
    variable ret: byte_string(v'range);
  begin
    for i in v'range
    loop
      ret(i) := not v(i);
    end loop;
    return ret;
  end function;
    
  function "and"(l, r : byte_string) return byte_string
  is
    alias xl: byte_string(0 to l'length-1) is l;
    alias xr: byte_string(0 to r'length-1) is r;
    variable ret: byte_string(0 to r'length-1);
  begin
    if xl'length /= xr'length then
      report "Passed vectors should be of the same size"
        severity failure;
      return null_byte_string;
    end if;

    for i in xl'range
    loop
      ret(i) := xl(i) and xr(i);
    end loop;
    return ret;
  end function;

  function "or"(l, r : byte_string) return byte_string
  is
    alias xl: byte_string(0 to l'length-1) is l;
    alias xr: byte_string(0 to r'length-1) is r;
    variable ret: byte_string(0 to r'length-1);
  begin
    if xl'length /= xr'length then
      report "Passed vectors should be of the same size"
        severity failure;
      return null_byte_string;
    end if;

    for i in xl'range
    loop
      ret(i) := xl(i) or xr(i);
    end loop;
    return ret;
  end function;

  function "xor"(l, r : byte_string) return byte_string
  is
    alias xl: byte_string(0 to l'length-1) is l;
    alias xr: byte_string(0 to r'length-1) is r;
    variable ret: byte_string(0 to r'length-1);
  begin
    if xl'length /= xr'length then
      report "Passed vectors should be of the same size"
        severity failure;
      return null_byte_string;
    end if;

    for i in xl'range
    loop
      ret(i) := xl(i) xor xr(i);
    end loop;
    return ret;
  end function;

  function first_left(s: byte_string) return byte
  is
  begin
    if s'length = 0 then
      return dontcare_byte_c;
    end if;
    return s(s'left);
  end function;

  function first_right(s: byte_string) return byte
  is
  begin
    if s'length = 0 then
      return dontcare_byte_c;
    end if;
    return s(s'right);
  end function;

end package body bytestream;
