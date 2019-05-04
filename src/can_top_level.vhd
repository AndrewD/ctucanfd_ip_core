--------------------------------------------------------------------------------
-- 
-- CTU CAN FD IP Core
-- Copyright (C) 2015-2018
-- 
-- Authors:
--     Ondrej Ille <ondrej.ille@gmail.com>
--     Martin Jerabek <martin.jerabek01@gmail.com>
-- 
-- Project advisors: 
-- 	Jiri Novak <jnovak@fel.cvut.cz>
-- 	Pavel Pisa <pisa@cmp.felk.cvut.cz>
-- 
-- Department of Measurement         (http://meas.fel.cvut.cz/)
-- Faculty of Electrical Engineering (http://www.fel.cvut.cz)
-- Czech Technical University        (http://www.cvut.cz/)
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this VHDL component and associated documentation files (the "Component"),
-- to deal in the Component without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Component, and to permit persons to whom the
-- Component is furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Component.
-- 
-- THE COMPONENT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHTHOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE COMPONENT OR THE USE OR OTHER DEALINGS
-- IN THE COMPONENT.
-- 
-- The CAN protocol is developed by Robert Bosch GmbH and protected by patents.
-- Anybody who wants to implement this IP core on silicon has to obtain a CAN
-- protocol license from Bosch.
-- 
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Purpose:
--  Enity encapsulating all functionality of CAN FD node.
--  Instances:
--      1x Memory registers
--      1x Interrupt manager
--      1x Prescaler (v3)
--      1x Bus synchronizes
--      1x Event Logger
--      1x Rx buffer
--      2x TXT buffer
--      1x Tx Arbitrator
--      1x Acceptance filters
--------------------------------------------------------------------------------
-- Revision History:
--    July 2015   Created file
--    22.6.2016   1. Added rec_esi signal for error state propagation into
--                   RX buffer.
--                2. Added explicit architecture selection for each component
--                   (RTL)
--    24.8.2016   Added "use_logger" generic to the registers module.
--    28.11.2017  Added "rst_sync_comp" reset synchroniser.
--    30.11.2017  Changed TXT buffer to registers interface. The user is now
--                directly accessing the buffer by avalon access.
--    10.12.2017  Added "tx_time_sup" to enable/disable transmission at given
--                time and save some LUTs.
--    12.12.2017  Renamed "registers" entity to  "canfd_registers" to avoid
--                possible name conflicts.
--    20.12.2017  Removed obsolete "tran_data_in" signal.
--     10.2.2017  Removed "useFDsize" generic. When TX Buffer goes completely
--                to the Dual port RAM, there is no need to save memory
--                anymore.
--     15.2.2018  Added generic amount of TXT Buffers and support for TXT
--                buffer FSM, HW commands and SW commands.
--     18.3.2019  Remove explicit architecture assignments.
--------------------------------------------------------------------------------

Library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.ALL;
use ieee.math_real.ALL;

Library work;
use work.id_transfer.all;
use work.can_constants.all;
use work.can_components.all;
use work.can_types.all;
use work.cmn_lib.all;
use work.drv_stat_pkg.all;
use work.endian_swap.all;
use work.reduce_lib.all;
use work.can_config.all;

use work.CAN_FD_register_map.all;
use work.CAN_FD_frame_format.all;

entity can_top_level is
    generic(
        -- Insert logger instance
        use_logger     : boolean                := true;

        -- RX Buffer RAM size (32 bit words)
        rx_buffer_size : natural range 32 to 4096 := 128;

        -- ID (bits 19-16 of adress)
        ID             : natural range 0 to 15  := 1;

        -- Insert Filter A
        sup_filtA      : boolean                := true;
        
        -- Insert Filter B
        sup_filtB      : boolean                := true;
        
        -- Insert Filter C
        sup_filtC      : boolean                := true;
        
        -- Insert Range Filter
        sup_range      : boolean                := true;
        
        -- Event Logger RAM size (32 bit words)
        logger_size    : natural range 0 to 512 := 8
    );
    port(
        -----------------------------------------------------------------------
        -- Clock and Asynchronous reset
        -----------------------------------------------------------------------
        -- System clock
        clk_sys     : in std_logic;
        
        -- Asynchronous reset
        res_n       : in std_logic;

        -----------------------------------------------------------------------
        -- Memory interface
        -----------------------------------------------------------------------
        -- Input data
        data_in     : in  std_logic_vector(31 downto 0);
        
        -- Output data
        data_out    : out std_logic_vector(31 downto 0);
        
        -- Address
        adress      : in  std_logic_vector(15 downto 0);
        
        -- Chip select
        scs         : in  std_logic;
        
        -- Read indication
        srd         : in  std_logic;
        
        -- Write indication
        swr         : in  std_logic;
        
        -- Byte enable
        sbe         : in  std_logic_vector(3 downto 0);
        
        -----------------------------------------------------------------------
        -- Interrupt Interface
        -----------------------------------------------------------------------
        -- Interrupt output
        int         : out std_logic;

        -----------------------------------------------------------------------
        -- CAN Bus Interface
        -----------------------------------------------------------------------
        -- TX signal to CAN bus
        can_tx      : out std_logic;
        
        -- RX signal from CAN bus
        can_rx      : in  std_logic;

        -----------------------------------------------------------------------
        -- Synchronisation signals
        -----------------------------------------------------------------------
        -- Time Quanta clocks
        time_quanta_clk : out std_logic;

        -----------------------------------------------------------------------
        -- Internal signals for testbenches
        -----------------------------------------------------------------------
        -- synthesis translate_off
        -- Driving Bus output
        drv_bus_o    : out std_logic_vector(1023 downto 0);
        
        -- Status Bus output
        stat_bus_o   : out std_logic_vector(511 downto 0);
        -- synthesis translate_on

        -----------------------------------------------------------------------
        -- Timestamp for time based transmission / reception
        -----------------------------------------------------------------------
        timestamp    : in std_logic_vector(63 downto 0)
    );
end entity CAN_top_level;

architecture rtl of CAN_top_level is

    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    ---- Internal signals
    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Common signals
    ----------------------------------------------------------------------------
    -- Driving Bus
    signal drv_bus      : std_logic_vector(1023 downto 0);
    
    -- Status Bus
    signal stat_bus     : std_logic_vector(511 downto 0);
    
    -- Synchronised reset
    signal res_n_sync   : std_logic;
    
    -- Internal reset (Synchronised reset + Soft Reset)
    signal res_n_i      : std_logic;
    
    -- Sample control (Nominal, Data, Secondary)
    signal sp_control   : std_logic_vector(1 downto 0);
    
    ----------------------------------------------------------------------------
    -- RX Buffer <-> Memory registers Interface
    ----------------------------------------------------------------------------
    -- Actual size of synthetised message buffer (in 32 bit words)
    signal rx_buf_size          :    std_logic_vector(12 downto 0);
    
    -- Signal whenever buffer is full (no free memory words)
    signal rx_full              :    std_logic;
    
    -- Signal whenever buffer is empty (no frame (message) is stored)
    signal rx_empty             :    std_logic;
    
    -- Number of frames (messages) stored in recieve buffer
    signal rx_message_count     :    std_logic_vector(10 downto 0);
    
    -- Number of free 32 bit wide words
    signal rx_mem_free          :    std_logic_vector(12 downto 0);
    
    -- Position of read pointer
    signal rx_read_pointer_pos  :    std_logic_vector(11 downto 0);
    
    -- Position of write pointer
    signal rx_write_pointer_pos :    std_logic_vector(11 downto 0);
    
    -- Overrun occurred, data were discarded!
    -- (This is a flag and persists until it is cleared by SW)! 
    signal rx_data_overrun      :    std_logic;
    
    -- Actually loaded data for reading from RX Buffer
    signal rx_read_buff         :    std_logic_vector(31 downto 0);

    ----------------------------------------------------------------------------
    -- TXT Buffer <-> Memory registers Interface
    ----------------------------------------------------------------------------
    -- TXT Buffer RAM - Data input
    signal txtb_port_a_data     :    std_logic_vector(31 downto 0);
    
    -- TXT Buffer RAM - Address
    signal txtb_port_a_address  :    std_logic_vector(4 downto 0);
    
    -- TXT Buffer chip select
    signal txtb_port_a_cs       :    std_logic_vector(G_TXT_BUFFER_COUNT - 1 downto 0);

    -- TXT Buffer status
    signal txtb_state           :    t_txt_bufs_state;

    -- SW Commands to TXT Buffer
    signal txtb_sw_cmd          :    t_txtb_sw_cmd;
    
    -- Command Index (Index in logic 1 means command is valid for buffer)          
    signal txtb_sw_cmd_index    :    std_logic_vector(G_TXT_BUFFER_COUNT - 1 downto 0);
    
    -- TXT Buffer priorities
    signal txtb_prorities       :    t_txt_bufs_priorities;

    ------------------------------------------------------------------------
    -- Event logger <-> Memory registers Interface
    ------------------------------------------------------------------------
    -- Logger RAM - Read Data
    signal loger_act_data       :     std_logic_vector(63 downto 0);
    
    -- Logger RAM - Write Pointer
    signal log_write_pointer    :     std_logic_vector(7 downto 0);
    
    -- Logger RAM - Read Pointer
    signal log_read_pointer     :     std_logic_vector(7 downto 0);
    
    -- Logger RAM - Size        
    signal log_size             :     std_logic_vector(7 downto 0);
    
    -- Logger FSM Status
    signal log_state_out        :     logger_state_type;
    
    ------------------------------------------------------------------------
    -- Interrupt Manager <-> Memory registers Interface
    ------------------------------------------------------------------------
    -- Interrupt vector
    signal int_vector   :     std_logic_vector(C_INT_COUNT - 1 downto 0);
    
    -- Interrupt enable
    signal int_ena      :     std_logic_vector(C_INT_COUNT - 1 downto 0);
    
    -- Interrupt mask
    signal int_mask     :     std_logic_vector(C_INT_COUNT - 1 downto 0);
    
    ------------------------------------------------------------------------
    -- RX Buffer <-> CAN Core Interface
    ------------------------------------------------------------------------
    -- Frame Identifier
    signal rec_ident        :     std_logic_vector(28 downto 0);
    
    -- Data length code
    signal rec_dlc          :     std_logic_vector(3 downto 0);
    
    -- Recieved identifier type (0-BASE Format, 1-Extended Format);
    signal rec_ident_type   :     std_logic;
    
    -- Recieved frame type (0-Normal CAN, 1- CAN FD)
    signal rec_frame_type   :     std_logic;
    
    -- Recieved frame is RTR Frame(0-No, 1-Yes)
    signal rec_is_rtr       :     std_logic;
    
    -- Whenever frame was recieved with BIT Rate shift 
    signal rec_brs          :     std_logic;

    -- Recieved error state indicator
    signal rec_esi          :     std_logic;
   
    -- Data word which should be stored when "store_data" is active!
    signal store_data_word  :     std_logic_vector(31 downto 0);

    -- Signals start of frame. If timestamp on RX frame should be captured
    -- in the beginning of the frame, this pulse captures the timestamp!
    signal sof_pulse        :     std_logic;

    ------------------------------------------------------------------------
    -- Frame filters <-> CAN Core Interface (Commands for RX Buffer)
    ------------------------------------------------------------------------
    -- After control field of CAN frame, metadata are valid and can be stored.
    -- This command starts the RX FSM for storing.
    signal store_metadata   :     std_logic;
    
    -- Signal that one word of data can be stored (TX_DATA_X_W). This signal
    -- is active when 4 bytes were received or data reception has finished 
    -- on 4 byte unaligned number of frames! (Thus allowing to store also
    -- data which are not 4 byte aligned!
    signal store_data       :     std_logic;

    -- Received frame valid (commit RX Frame)
    signal rec_valid        :     std_logic;
    
    -- Abort storing of RX Frame to RX Buffer.
    signal rec_abort        :     std_logic;
    
    -- Filtered version of RX Buffer commands
    signal store_metadata_f :     std_logic;
    signal store_data_f     :     std_logic;
    signal rec_valid_f      :     std_logic;
    signal rec_abort_f      :     std_logic;
    
    ------------------------------------------------------------------------
    -- TXT Buffers <-> Interrrupt Manager Interface
    ------------------------------------------------------------------------
    -- TXT HW Commands Applied Interrupt
    signal txtb_hw_cmd_int : std_logic_vector(C_TXT_BUFFER_COUNT - 1 downto 0);

    ------------------------------------------------------------------------
    -- TXT Buffers <-> CAN Core Interface
    ------------------------------------------------------------------------    
    -- HW Commands 
    signal txtb_hw_cmd            :   t_txtb_hw_cmd;

    -- Unit just turned bus off.
    signal is_bus_off             :   std_logic;

    ------------------------------------------------------------------------
    -- TXT Buffers <-> TX Arbitrator
    ------------------------------------------------------------------------    
    -- Index of TXT Buffer for which HW commands is valid          
    signal txtb_hw_cmd_index   :   natural range 0 to G_TXT_BUF_COUNT - 1;
    
    -- TXT Buffers are ready, can be selected by TX Arbitrator
    signal txtb_ready          :   std_logic_vector(G_TXT_BUFFER_COUNT - 1 downto 0);
        
    -- Pointer to TXT Buffer
    signal txtb_ptr            :   natural range 0 to 19;
    
    -- TXT Buffer RAM data outputs
    signal txtb_port_b_data    :   t_txt_bufs_output;
    
    -- TXT Buffer RAM address
    signal txtb_port_b_address :   natural range 0 to 19;
    
    ------------------------------------------------------------------------
    -- CAN Core <-> TX Arbitrator
    ------------------------------------------------------------------------    
    -- TX Data length code
    signal tran_dlc               :   std_logic_vector(3 downto 0);
    
    -- TX Remote transmission request flag
    signal tran_is_rtr            :   std_logic;

    -- TX Identifier type (0-Basic,1-Extended);
    signal tran_ident_type        :   std_logic;
    
    -- TX Frame type (0-CAN 2.0, 1-CAN FD)
    signal tran_frame_type        :   std_logic;
    
    -- TX Frame Bit rate shift Flag 
    signal tran_brs               :   std_logic;
    
    -- Word from TXT Buffer RAM selected by TX Arbitrator
    signal tran_word              :   std_logic_vector(31 downto 0);
    
    -- Valid frame is selected from transmission on output of TX Arbitrator.
    -- CAN Core may lock TXT Buffer for transmission!
    signal tran_frame_valid       :   std_logic;
    
    -- Selected TXT Buffer index changed
    signal txtb_changed           :   std_logic;
    
    ------------------------------------------------------------------------
    -- CAN Core <-> Interrupt manager
    ------------------------------------------------------------------------    
    -- Error appeared
    signal err_detected            :   std_logic;

    -- Error pasive /Error acitve functionality changed
    signal error_passive_changed   :   std_logic;

    -- Error warning limit reached
    signal error_warning_limit     :   std_logic;

    -- Arbitration was lost input
    signal arbitration_lost        :   std_logic;

    -- Transmitted frame is valid
    signal tran_valid              :   std_logic;

    -- Bit Rate Was Shifted
    signal br_shifted              :   std_logic;
    
    ------------------------------------------------------------------------
    -- CAN Core <-> Prescaler Interface
    ------------------------------------------------------------------------
    -- RX Triggers (Sample)  
    signal rx_triggers   : std_logic_vector(C_SAMPLE_TRIGGER_COUNT - 1 downto 0);
    
    -- TX Trigger (Sync)
    signal tx_trigger    : std_logic;
    
    -- Synchronisation control (No synchronisation, Hard Synchronisation,
    -- Resynchronisation
    signal sync_control  : std_logic_vector(1 downto 0);
    
    -- No positive resynchronisation 
    signal no_pos_resync : std_logic;
    
    ------------------------------------------------------------------------
    -- Bus Sampling <-> Memory Registers Interface
    ------------------------------------------------------------------------
    -- Measured Transceiver delay 
    signal trv_delay     : std_logic_vector(15 downto 0);
    
    ------------------------------------------------------------------------
    -- Bus Sampling <-> CAN Core Interface
    ------------------------------------------------------------------------
    -- RX Data With Bit Stuffing
    signal rx_data_wbs          : std_logic;
    
    -- TX Data With Bit Stuffing
    signal tx_data_wbs          : std_logic;
    
    -- Secondary sample point reset
    signal ssp_reset            :  std_logic; 

    -- Enable measurement of Transciever delay
    signal trv_delay_calib      :  std_logic;

    -- Bit Error detected 
    signal bit_error            :  std_logic;
        
    -- Secondary sample signal 
    signal sample_sec           :  std_logic;
    
    ------------------------------------------------------------------------
    -- Bus Sampling <-> Prescaler Interface
    ------------------------------------------------------------------------
    signal sync_edge            :  std_logic;
    
    ------------------------------------------------------------------------
    -- Event Logger Status signals
    ------------------------------------------------------------------------
    -- Logging finished
    signal loger_finished       :  std_logic;
    
begin

    -- synthesis translate_off
    drv_bus_o   <= drv_bus;
    stat_bus_o  <= stat_bus;
    -- synthesis translate_on

    ---------------------------------------------------------------------------
    -- Reset synchroniser
    ---------------------------------------------------------------------------
    rst_sync_comp : rst_sync
    generic map(
        reset_polarity  => C_RESET_POLARITY
    )
    port map(
        clk             => clk_sys,
        arst            => res_n,
        rst             => res_n_sync
    );

    ---------------------------------------------------------------------------
    -- Memory registers
    ---------------------------------------------------------------------------
    memory_registers_inst : memory_registers
    generic map(
        G_RESET_POLARITY    => C_RESET_POLARITY,
        G_USE_LOGGER        => use_logger,
        G_SUP_FILTA         => sup_filtA,
        G_SUP_FILTB         => sup_filtB,
        G_SUP_FILTC         => sup_filtC,
        G_SUP_RANGE         => sup_range,
        G_TXT_BUFFER_COUNT  => C_TXT_BUFFER_COUNT, 
        G_ID                => ID,
        G_INT_COUNT         => C_INT_COUNT,
        G_DEVICE_ID         => C_DEVICE_ID,
        G_VERSION_MINOR     => C_VERSION_MINOR,
        G_VERSION_MAJOR     => C_VERSION_MAJOR
    )
    port map(
        clk_sys             => clk_sys,
        res_n               => res_n_sync,
        res_out             => res_n_i,

        -- Memory Interface
        data_in             => data_in,
        data_out            => data_out,
        adress              => adress,
        scs                 => scs,
        srd                 => srd,
        swr                 => swr,
        sbe                 => sbe,
        timestamp           => timestamp,
        
        -- Buses to/from rest of CTU CAN FD
        drv_bus             => drv_bus,
        stat_bus            => stat_bus,

        -- RX Buffer Interface
        rx_read_buff         => rx_read_buff,
        rx_buf_size          => rx_buf_size,
        rx_full              => rx_full,
        rx_empty             => rx_empty,
        rx_message_count     => rx_message_count,
        rx_mem_free          => rx_mem_free,
        rx_read_pointer_pos  => rx_read_pointer_pos,
        rx_write_pointer_pos => rx_write_pointer_pos,
        rx_data_overrun      => rx_data_overrun,

        -- Interface to TXT Buffers
        txtb_port_a_data     => txtb_port_a_data,
        txtb_port_a_address  => txtb_port_a_address,
        txtb_port_a_cs       => txtb_port_a_cs,
        txtb_state           => txtb_state,
        txtb_sw_cmd          => txtb_sw_cmd,
        txtb_sw_cmd_index    => txtb_sw_cmd_index,
        txtb_prorities       => txtb_prorities,
         
        -- Bus synchroniser interface
        trv_delay            => trv_delay,

        -- Event logger interface
        loger_act_data       => loger_act_data,
        log_write_pointer    => log_write_pointer,
        log_read_pointer     => log_read_pointer,
        log_size             => log_size,
        log_state_out        => log_state_out,
            
        -- Interrrupt Interface
        int_vector           => int_vector,
        int_ena              => int_ena,
        int_mask             => int_mask
    );

    ---------------------------------------------------------------------------
    -- RX Buffer
    ---------------------------------------------------------------------------
    rx_buffer_inst : rx_buffer
    generic map(
        G_RESET_POLARITY    => C_RESET_POLARITY,
        G_RX_BUFF_SIZE      => rx_buffer_size
    )
    port map(
        clk_sys             => clk_sys,
        res_n               => res_n_i,

        -- Metadata from CAN Core
        rec_ident           => rec_ident,
        rec_dlc             => rec_dlc,
        rec_ident_type      => rec_ident_type,
        rec_frame_type      => rec_frame_type,
        rec_is_rtr          => rec_is_rtr,
        rec_brs             => rec_brs,
        rec_esi             => rec_esi,

        -- Control signals from CAN Core which control storing of CAN Frame.
        -- Filtered by Frame filters.
        store_metadata_f    => store_metadata_f,
        store_data_f        => store_data_f,
        store_data_word     => store_data_word,
        rec_valid_f         => rec_valid_f,
        rec_abort_f         => rec_abort_f,
        sof_pulse           => sof_pulse,

        -- Status signals of recieve buffer
        rx_buf_size          => rx_buf_size,
        rx_full              => rx_full,
        rx_empty             => rx_empty,
        rx_message_count     => rx_message_count,
        rx_mem_free          => rx_mem_free,
        rx_read_pointer_pos  => rx_read_pointer_pos,
        rx_write_pointer_pos => rx_write_pointer_pos,
        rx_data_overrun      => rx_data_overrun,
        
        -- External timestamp input
        timestamp            => timestamp,

        -- Memory registers interface
        rx_read_buff         => rx_read_buff,
        drv_bus              => drv_bus
    );

    ---------------------------------------------------------------------------
    -- TXT Buffers
    ---------------------------------------------------------------------------
    txt_buf_comp_gen : for i in 0 to C_TXT_BUFFER_COUNT - 1 generate
        txt_buffer_inst : txt_buffer
        generic map(
            G_RESET_POLARITY       => C_RESET_POLARITY,
            G_TXT_BUF_COUNT        => C_TXT_BUF_COUNT,
            G_ID                   => i
        )
        port map(
            clk_sys                => clk_sys,
            res_n                  => res_n_i,

            -- Memory Registers Interface
            txtb_port_a_data       => txtb_port_a_data,
            txtb_port_a_address    => txtb_port_a_address,
            txtb_port_a_cs         => txtb_port_a_cs,
            txtb_sw_cmd            => txtb_sw_cmd,
            txtb_sw_cmd_index      => txtb_sw_cmd_index,
            txtb_state             => txtb_state,
    
            -- Interrupt Manager Interface
            txtb_hw_cmd_int        => txtb_hw_cmd_int(i),
    
            -- CAN Core and TX Arbitrator Interface
            txtb_hw_cmd            => txtb_hw_cmd,
            txtb_hw_cmd_index      => txtb_hw_cmd_index,
            txtb_port_b_data       => txtb_port_b_data(i),
            txtb_port_b_address    => txtb_port_b_address,
            is_bus_off             => is_bus_off,
            txtb_ready             => txtb_ready(i)
        );
    end generate;

    ---------------------------------------------------------------------------
    -- TX Arbitrator
    ---------------------------------------------------------------------------
    tx_arbitrator_inst : tx_arbitrator
    generic map(
        G_RESET_POLARITY        => C_RESET_POLARITY,
        C_TXT_BUFFER_COUNT      => C_TXT_BUFFER_COUNT
    )
    port map( 
        clk_sys                 => clk_sys,
        res_n                   => res_n_i,

        -- TXT Buffers interface
        txtb_port_b_data        => txtb_port_b_data,
        txtb_ready              => txtb_ready,
        txtb_ptr                => txtb_ptr,

        -- CAN Core Interface
        tran_word               => tran_word,
        tran_dlc                => tran_dlc,
        tran_is_rtr             => tran_is_rtr,
        tran_ident_type         => tran_ident_type,
        tran_frame_type         => tran_frame_type,
        tran_brs                => tran_brs,
        tran_frame_valid        => tran_frame_valid,
        txtb_hw_cmd             => txtb_hw_cmd,
        txtb_changed            => txtb_changed,
        txtb_hw_cmd_index       => txtb_hw_cmd_index,
        txtb_ptr                => txtb_ptr,

        -- Memory registers interface
        drv_bus                 => drv_bus,
        txtb_prorities          => txtb_prorities,
        timestamp               => timestamp
    );

    ---------------------------------------------------------------------------
    -- Frame Filters
    ---------------------------------------------------------------------------
    frame_filters_inst : frame_filters
    generic map(
        G_RESET_POLARITY       => C_RESET_POLARITY,
        G_SUP_FILTA            => sup_filtA,
        G_SUP_FILTB            => sup_filtB,
        G_SUP_FILTC            => sup_filtC,
        G_SUP_RANGE            => sup_range
    )
    port map(
        clk_sys             => clk_sys,       
        res_n               => res_n_i,

        -- Memory registers interface
        drv_bus             => drv_bus,

        -- CAN Core interface
        rec_ident           => rec_ident,
        ident_type          => rec_ident_type,
        frame_type          => rec_frame_type,
        store_metadata      => store_metadata,
        store_data          => store_data,
        rec_valid           => rec_valid,
        rec_abort           => rec_abort,

        -- Frame filters output
        ident_valid         => open,
        store_metadata_f    => store_metadata_f,
        store_data_f        => store_data_f,
        rec_valid_f         => rec_valid_f,
        rec_abort_f         => rec_abort_f
    );

    ---------------------------------------------------------------------------
    -- Interrrupt Manager
    ---------------------------------------------------------------------------
    int_manager_inst : int_manager
    generic map(
        G_RESET_POLARITY     => C_RESET_POLARITY,
        G_INT_COUNT          => C_INT_COUNT,
        G_TXT_BUFFER_COUNT   => C_TXT_BUFFER_COUNT
    )
    port map(
        clk_sys                 => clk_sys,
        res_n                   => res_n_i,

        -- Interrupt sources
        err_detected            => err_detected,
        error_passive_changed   => error_passive_changed,
        error_warning_limit     => error_warning_limit,
        arbitration_lost        => arbitration_lost,
        tran_valid              => tran_valid,
        br_shifted              => br_shifted,
        rx_data_overrun         => rx_data_overrun,
        rec_valid               => rec_valid,
        rx_full                 => rx_full,
        rx_empty                => rx_empty,
        txtb_hw_cmd_int         => txtb_hw_cmd_int,
        loger_finished          => loger_finished,

        -- Memory registers Interface
        drv_bus                 => drv_bus,
        int                     => int,
        int_vector              => int_vector,
        int_mask                => int_mask,
        int_ena                 => int_ena
    );

    ---------------------------------------------------------------------------
    -- CAN Core
    ---------------------------------------------------------------------------
    can_core_inst : can_core
    generic map(
        G_RESET_POLARITY        => C_RESET_POLARITY,
        G_SAMPLE_TRIGGER_COUNT  => C_SAMPLE_TRIGGER_COUNT,
        G_CTRL_CTR_WIDTH        => C_CTRL_CTR_WIDTH,
        G_RETR_LIM_CTR_WIDTH    => C_RETR_LIM_CTR_WIDTH,
        G_ERR_VALID_PIPELINE    => C_ERR_VALID_PIPELINE,
        G_CRC15_POL             => C_CRC15_POL,
        G_CRC17_POL             => C_CRC15_POL,
        G_CRC21_POL             => C_CRC15_POL
    )
    port map(
        clk_sys                 => clk_sys,
        res_n                   => res_n_i,
        
        -- Memory registers interface
        drv_bus                 => drv_bus,
        stat_bus                => stat_bus,

        -- Tx Arbitrator and TXT Buffers interface
        tran_word               => tran_word,
        tran_dlc                => tran_dlc,
        tran_is_rtr             => tran_is_rtr,
        tran_ident_type         => tran_ident_type,
        tran_frame_type         => tran_frame_type,
        tran_brs                => tran_brs,
        tran_frame_valid        => tran_frame_valid,
        txtb_hw_cmd             => txtb_hw_cmd,
        txtb_changed            => txtb_changed,
        txtb_ptr                => txtb_ptr,
        is_bus_off              => is_bus_off,

        -- Recieve Buffer and Message Filter Interface
        rec_ident               => rec_ident,
        rec_dlc                 => rec_dlc,
        rec_ident_type          => rec_ident_type,
        rec_frame_type          => rec_frame_type,
        rec_is_rtr              => rec_is_rtr,
        rec_brs                 => rec_brs,
        rec_esi                 => rec_esi,
        rec_valid               => rec_valid,
        store_metadata          => store_metadata,
        store_data              => store_data,
        store_data_word         => store_data_word,
        rec_abort               => rec_abort,
        sof_pulse               => sof_pulse,

        -- Interrupt Manager Interface 
        arbitration_lost        => arbitration_lost,
        tran_valid              => tran_valid,
        br_shifted              => br_shifted,
        err_detected            => err_detected,
        error_passive_changed   => error_passive_changed,
        error_warning_limit     => error_warning_limit,

        -- Prescaler interface 
        rx_triggers             => rx_triggers,
        tx_trigger              => tx_trigger,
        sync_control            => sync_control,
        no_pos_resync           => no_pos_resync,

        -- CAN Bus serial data stream
        rx_data_wbs             => rx_data_wbs,
        tx_data_wbs             => tx_data_wbs,

        -- Others
        timestamp               => timestamp,
        sp_control              => sp_control,
        ssp_reset               => ssp_reset,
        trv_delay_calib         => trv_delay_calib,
        bit_error               => bit_error,
        sample_sec              => sample_sec
    );
    
    
    ---------------------------------------------------------------------------
    -- Prescaler
    ---------------------------------------------------------------------------
    prescaler_inst : prescaler
    generic map(
        G_RESET_POLARITY        => C_RESET_POLARITY,
        G_TSEG1_NBT_WIDTH       => C_TSEG1_NBT_WIDTH,
        G_TSEG2_NBT_WIDTH       => C_TSEG2_NBT_WIDTH,
        G_BRP_NBT_WIDTH         => C_BRP_NBT_WIDTH,
        G_SJW_NBT_WIDTH         => C_SJW_NBT_WIDTH,
        G_TSEG1_DBT_WIDTH       => C_TSEG1_DBT_WIDTH,
        G_TSEG2_DBT_WIDTH       => C_TSEG2_DBT_WIDTH,
        G_BRP_DBT_WIDTH         => C_BRP_DBT_WIDTH,
        G_SJW_DBT_WIDTH         => C_SJW_DBT_WIDTH,
        G_SAMPLE_TRIGGER_COUNT  => C_SAMPLE_TRIGGER_COUNT
    )
    port map(
        clk_sys                 => clk_sys, 
        res_n                   => res_n_i,
        
        -- Memory registers interface
        drv_bus                 => drv_bus,
        
        -- Control Interface
        sync_edge               => sync_edge,
        sp_control              => sp_control,
        sync_control            => sync_control,
        no_pos_resync           => no_pos_resync,
        
        -- Trigger signals
        rx_triggers             => rx_triggers,
        tx_trigger              => tx_trigger,
        
        -- Status outputs
        time_quanta_clk         => time_quanta_clk
    );
  
 
    ---------------------------------------------------------------------------
    -- Bus Sampling
    ---------------------------------------------------------------------------
    bus_sampling_inst : bus_sampling 
    generic map(
        G_RESET_POLARITY        => C_RESET_POLARITY,
        G_SSP_SHIFT_LENGTH      => C_SSP_SHIFT_LENGTH,
        G_TX_CACHE_DEPTH        => C_TX_CACHE_DEPTH,
        G_TRV_CTR_WIDTH         => C_TRV_CTR_WIDTH,
        G_USE_SSP_SATURATION    => C_USE_SSP_SATURATION
    )
    port map(
        clk_sys                 => clk_sys,
        res_n                   => res_n_i,

        -- Physical layer interface
        can_rx                  => can_rx,
        can_tx                  => can_tx,

        -- Memory registers interface
        drv_bus                 => drv_bus,
        trv_delay               => trv_delay,

        -- Prescaler interface
        rx_trigger              => rx_triggers(1),
        sync_edge               => sync_edge,

        -- CAN Core Interface
        data_tx                 => tx_data_wbs,
        data_rx                 => rx_data_wbs,
        sp_control              => sp_control,
        ssp_reset               => ssp_reset,
        trv_delay_calib         => trv_delay_calib,
        sample_sec              => sample_sec,
        bit_error               => bit_error
    );
    

    ---------------------------------------------------------------------------
    -- Event Logger
    ---------------------------------------------------------------------------
    event_logger_gen_true : if (use_logger) generate
        event_logger_inst : event_logger
        generic map(
            memory_size         => logger_size
        )
        port map(
            clk_sys             => clk_sys,
            res_n               => res_n_i,

            drv_bus             => drv_bus,
            stat_bus            => stat_bus,
            sync_edge           => sync_edge,
            timestamp           => timestamp,

            loger_finished      => loger_finished,
            loger_act_data      => loger_act_data,
            log_write_pointer   => log_write_pointer,
            log_read_pointer    => log_read_pointer,
            log_size            => log_size,
            log_state_out       => log_state_out,
            data_overrun        => rx_data_overrun
        );
    end generate event_logger_gen_true;

    event_logger_gen_false : if (not use_logger) generate
        loger_finished    <= '0';
        loger_act_data    <= (others => '0');
        log_write_pointer <= (others => '0');
        log_read_pointer  <= (others => '0');
        log_size          <= (others => '0');
		log_state_out     <= config;
    end generate event_logger_gen_false;

end architecture;