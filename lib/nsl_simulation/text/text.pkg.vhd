library ieee, nsl_data, nsl_math;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use nsl_data.bytestream.all;
use nsl_math.fixed.all;

package text is

  function to_string(v: in std_ulogic_vector) return string;
  function to_string(v: in std_logic_vector) return string;
  function to_string(v: in std_ulogic) return string;
  function to_string(v: in bit_vector) return string;
  function to_string(v: in real) return string;
  function to_string(v: in integer) return string;
  function to_string(v: in boolean) return string;
  function to_string(v: in unsigned) return string;
  function to_string(data : byte_string) return string;
  function to_string(value: sfixed) return string;
  function to_string(value: ufixed) return string;
  function to_string(value: time) return string;

  function to_hex_string(data : byte_string) return string;
  function to_hex_string(v: in std_ulogic_vector) return string;
  function to_hex_string(v: in std_logic_vector) return string;
  function to_hex_string(v: in bit_vector) return string;

  -- Returns an index to add to haystack'left. If returns -1, needle
  -- is not found.
  function strchr(haystack : string;
                  needle : character;
                  start_index : integer := 0) return integer;
  -- Search for needle, either at begin/end of string, or separated by
  -- separator.
  function strfind(haystack, needle : string;
                   separator : character) return boolean;
  -- Search for needle in haystack (like libc's strstr, with inverted
  -- response boolean value)
  function strfind(haystack, needle : string) return boolean;

end package;

package body text is

  function to_string(v : in std_ulogic) return string is
  begin
    case v is
      when 'X' => return "X";
      when 'U' => return "U";
      when 'Z' => return "Z";
      when '0' => return "0";
      when '1' => return "1";
      when '-' => return "-";
      when 'W' => return "W";
      when 'H' => return "H";
      when 'L' => return "L";
      when others => return "0";
    end case;
  end function;    

  function to_string(v: in std_ulogic_vector) return string is
    variable c: character;
    variable ret: line := new string'("");
  begin
    for i in v'range loop
      write(ret, to_string(v(i)));
    end loop;

    return ret.all;
  end function to_string;

  function to_string(v: in real) return string is
    variable ret: line := new string'("");
  begin
    write(ret, v);
    return ret.all;
  end function to_string;

  function to_string(v: in integer) return string is
    variable ret: line := new string'("");
  begin
    write(ret, v);
    return ret.all;
  end function to_string;

  function to_string(v: in std_logic_vector) return string is
  begin
    return to_string(std_ulogic_vector(v));
  end function;

  function to_string(v: in bit_vector) return string is
  begin
    return to_string(to_stdulogicvector(v));
  end function;

  function to_string(data : byte_string) return string is
    variable ret : line := new string'("");
  begin
    write(ret, string'("["), left, 1);
    for i in data'range
    loop
      if i /= data'left then
        write(ret, string'(" "), left, 1);
      end if;
      write(ret, to_hex_string(data(i)), left, 2);
    end loop;
    write(ret, string'("]"), left, 1);

    return ret.all;
  end function;

  function to_string(v: in unsigned) return string
  is
  begin
    return "x""" & to_hex_string(std_ulogic_vector(v)) & """";
  end function;

  function to_hex_string(data : byte_string) return string is
    alias din : byte_string(0 to data'length-1) is data;
    variable ret : string(0 to data'length*2-1);
  begin
    for i in din'range
    loop
      ret(i*2 to i*2+1) := to_hex_string(std_ulogic_vector(din(i)));
    end loop;

    return ret;
  end function;

  function to_hex_string(v: in bit_vector) return string is
    variable ret: string(1 to (v'length + 3) / 4);
    constant pad : bit_vector(1 to ret'length*4 - v'length) := (others => '0');
    constant t : bit_vector(4  to ret'length*4+3) := pad & v;
    variable nibble : bit_vector(3 downto 0);
    variable c : character;
  begin
    for i in ret'range loop
      nibble := t(4 * i to 4 * i + 3);
      case nibble is
        when "0000" => c := '0';
        when "0001" => c := '1';
        when "0010" => c := '2';
        when "0011" => c := '3';
        when "0100" => c := '4';
        when "0101" => c := '5';
        when "0110" => c := '6';
        when "0111" => c := '7';
        when "1000" => c := '8';
        when "1001" => c := '9';
        when "1010" => c := 'a';
        when "1011" => c := 'b';
        when "1100" => c := 'c';
        when "1101" => c := 'd';
        when "1110" => c := 'e';
        when others => c := 'f';
      end case;
      ret(i) := c;
    end loop;

    return ret;
  end function to_hex_string;

  function to_hex_string(v: in std_ulogic_vector) return string is
  begin
    return to_hex_string(to_bitvector(v));
  end function;

  function to_hex_string(v: in std_logic_vector) return string is
  begin
    return to_hex_string(to_bitvector(v));
  end function;

  function to_string(value: ufixed) return string
  is
    constant int : string := to_string(to_suv(value(value'left downto 0)));
    constant frac : string := to_string(to_suv(value(-1 downto value'right)));
  begin
    return int & "." & frac;
  end function;

  function to_string(value: sfixed) return string
  is
    constant int : string := to_string(to_suv(value(value'left downto 0)));
    constant frac : string := to_string(to_suv(value(-1 downto value'right)));
  begin
    return int & "." & frac;
  end function;

  function to_string(v: in boolean) return string
  is
  begin
    if v then
      return "true";
    else
      return "false";
    end if;
  end function;

  function strchr(haystack : string;
                  needle : character;
                  start_index : integer := 0) return integer
  is
  begin
    if start_index >= haystack'length or start_index < 0 then
      return -1;
    end if;

    for offset in haystack'left + start_index to haystack'right
    loop
      if haystack(offset) = needle then
        return offset;
      end if;
    end loop;

    return -1;
  end function;

  function to_string(value: time) return string
  is
  begin
    return time'image(value);
  end function;

  function strfind(haystack, needle : string) return boolean
  is
  begin
    if needle'length > haystack'length then
      return false;
    end if;

    for offset in haystack'left to haystack'right - needle'length + 1
    loop
      if haystack(offset to offset + needle'length - 1) = needle then
        return true;
      end if;
    end loop;

    return false;
  end function;

  function strfind(haystack, needle : string;
                   separator : character) return boolean
  is
  begin
    return strfind(separator & haystack & separator, needle);
  end function;

end package body;

