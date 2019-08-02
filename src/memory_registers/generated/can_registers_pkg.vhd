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
-- Register map package for: CAN_Registers
--------------------------------------------------------------------------------
-- This file is autogenerated, DO NOT EDIT!

Library ieee;
use ieee.std_logic_1164.all;

package can_registers_pkg is

  type Control_registers_out_t is record
     mode                        : std_logic_vector(15 downto 0);
     settings                    : std_logic_vector(15 downto 0);
     command                     : std_logic_vector(31 downto 0);
     int_stat                    : std_logic_vector(15 downto 0);
     int_ena_set                 : std_logic_vector(15 downto 0);
     int_ena_clr                 : std_logic_vector(15 downto 0);
     int_mask_set                : std_logic_vector(15 downto 0);
     int_mask_clr                : std_logic_vector(15 downto 0);
     btr                         : std_logic_vector(31 downto 0);
     btr_fd                      : std_logic_vector(31 downto 0);
     ewl                         : std_logic_vector(7 downto 0);
     erp                         : std_logic_vector(7 downto 0);
     ctr_pres                    : std_logic_vector(31 downto 0);
     filter_a_mask               : std_logic_vector(31 downto 0);
     filter_a_val                : std_logic_vector(31 downto 0);
     filter_b_mask               : std_logic_vector(31 downto 0);
     filter_b_val                : std_logic_vector(31 downto 0);
     filter_c_mask               : std_logic_vector(31 downto 0);
     filter_c_val                : std_logic_vector(31 downto 0);
     filter_ran_low              : std_logic_vector(31 downto 0);
     filter_ran_high             : std_logic_vector(31 downto 0);
     filter_control              : std_logic_vector(15 downto 0);
     rx_settings                 : std_logic_vector(7 downto 0);
     rx_data_read                : std_logic;
     tx_command                  : std_logic_vector(15 downto 0);
     tx_priority                 : std_logic_vector(15 downto 0);
     ssp_cfg                     : std_logic_vector(15 downto 0);
  end record;


  type Control_registers_in_t is record
     device_id                   : std_logic_vector(15 downto 0);
     version                     : std_logic_vector(15 downto 0);
     status                      : std_logic_vector(31 downto 0);
     int_stat                    : std_logic_vector(15 downto 0);
     int_ena_set                 : std_logic_vector(15 downto 0);
     int_mask_set                : std_logic_vector(15 downto 0);
     fault_state                 : std_logic_vector(15 downto 0);
     rxc                         : std_logic_vector(15 downto 0);
     txc                         : std_logic_vector(15 downto 0);
     err_norm                    : std_logic_vector(15 downto 0);
     err_fd                      : std_logic_vector(15 downto 0);
     filter_status               : std_logic_vector(15 downto 0);
     rx_mem_info                 : std_logic_vector(31 downto 0);
     rx_pointers                 : std_logic_vector(31 downto 0);
     rx_status                   : std_logic_vector(15 downto 0);
     rx_data                     : std_logic_vector(31 downto 0);
     tx_status                   : std_logic_vector(15 downto 0);
     err_capt                    : std_logic_vector(7 downto 0);
     alc                         : std_logic_vector(7 downto 0);
     trv_delay                   : std_logic_vector(15 downto 0);
     rx_counter                  : std_logic_vector(31 downto 0);
     tx_counter                  : std_logic_vector(31 downto 0);
     debug_register              : std_logic_vector(31 downto 0);
     yolo_reg                    : std_logic_vector(31 downto 0);
     timestamp_low               : std_logic_vector(31 downto 0);
     timestamp_high              : std_logic_vector(31 downto 0);
  end record;

end package;
