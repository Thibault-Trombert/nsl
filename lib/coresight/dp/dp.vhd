library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, signalling;
use nsl.framed.all;

package dp is
  constant DP_CMD_RUN           : std_ulogic_vector(7 downto 0):= "0-------";
  constant DP_CMD_RUN_0         : std_ulogic_vector(7 downto 0):= "00------";
  constant DP_CMD_RUN_1         : std_ulogic_vector(7 downto 0):= "01------";
  constant DP_CMD_TURNAROUND    : std_ulogic_vector(7 downto 0):= "110100--";
  constant DP_CMD_ABORT         : std_ulogic_vector(7 downto 0):= "1100----";
  constant DP_CMD_BITBANG       : std_ulogic_vector(7 downto 0):= "111-----";
  constant DP_CMD_RW            : std_ulogic_vector(7 downto 0):= "10------";
  constant DP_CMD_W             : std_ulogic_vector(7 downto 0):= "10-0----";
  constant DP_CMD_R             : std_ulogic_vector(7 downto 0):= "10-1----";
  constant DP_CMD_AP_READ       : std_ulogic_vector(7 downto 0):= "1011----";
  constant DP_CMD_AP_WRITE      : std_ulogic_vector(7 downto 0):= "1010----";
  constant DP_CMD_DP_READ       : std_ulogic_vector(7 downto 0):= "1001----";
  constant DP_CMD_DP_WRITE      : std_ulogic_vector(7 downto 0):= "1000----";

  constant DP_RSP_ACK          : std_ulogic_vector(7 downto 0):= "-----001";
  constant DP_RSP_WAIT         : std_ulogic_vector(7 downto 0):= "-----010";
  constant DP_RSP_ERROR        : std_ulogic_vector(7 downto 0):= "-----100";
  constant DP_RSP_PAR_OK       : std_ulogic_vector(7 downto 0):= "----0---";
  constant DP_RSP_PAR_ERROR    : std_ulogic_vector(7 downto 0):= "----1---";
  
  type dp_cmd_data is record
    data : std_ulogic_vector(31 downto 0);
    op   : std_ulogic_vector(7 downto 0);
  end record;

  type dp_rsp_data is record
    data   : std_ulogic_vector(31 downto 0);
    ack    : std_ulogic_vector(2 downto 0);
    par_ok : std_ulogic;
  end record;

  component dp_framed_swdp
    port (
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_clk_tick : in  std_ulogic;

      p_cmd_val   : in nsl.framed.framed_req;
      p_cmd_ack   : out nsl.framed.framed_ack;

      p_rsp_val   : out nsl.framed.framed_req;
      p_rsp_ack   : in nsl.framed.framed_ack;

      p_swd_c     : out signalling.swd.swd_master_c;
      p_swd_s     : in  signalling.swd.swd_master_s
      );
  end component;

  component dp_transactor
    port (
      p_clk      : in  std_ulogic;
      p_resetn   : in  std_ulogic;

      p_clk_tick : in  std_ulogic;

      p_cmd_val  : in  std_ulogic;
      p_cmd_ack  : out std_ulogic;
      p_cmd_data : in  dp_cmd_data;

      p_rsp_val  : out std_ulogic;
      p_rsp_ack  : in  std_ulogic;
      p_rsp_data : out dp_rsp_data;

      p_swd_c    : out signalling.swd.swd_master_c;
      p_swd_s    : in  signalling.swd.swd_master_s
      );
  end component;

end dp;
