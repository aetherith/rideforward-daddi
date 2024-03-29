{{File: MCP2515.spin}}
{{

┌───────────────────────────────────┬─────────────────────────────────────────┬───────────────┐
│ Example Use of MCP2515 SPI Eng.   │ (C)2007 Stephen Moraco, KZ0Q            │ 08 Dec 2007   │
├───────────────────────────────────┴─────────────────────────────────────────┴───────────────┤
│  This program is free software; you can redistribute it and/or                              │
│  modify it under the terms of the GNU General Public License as published                   │
│  by the Free Software Foundation; either version 2 of the License, or                       │
│  (at your option) any later version.                                                        │
│                                                                                             │
│  This program is distributed in the hope that it will be useful,                            │
│  but WITHOUT ANY WARRANTY; without even the implied warranty of                             │
│  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                              │
│  GNU General Public License for more details.                                               │
│                                                                                             │
│  You should have received a copy of the GNU General Public License                          │
│  along with this program; if not, write to the Free Software                                │
│  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA                  │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│    NOTE   NOTE   NOTE   NOTE   NOTE   NOTE    │
│                                                                                             │
│    THIS IS NOT DEMO code in that you won't be able to compile download and run it.          │
│                                                                                             │
│    THIS IS a somewhat verbose code selection from an actual project under development.      │
│                                                                                             │
│    THIS DOES serve as a rich set of examples for interacting with the MCP2515 SPI Engine.   │
│                                                                                             │
│    THIS DOES serve as a possible foundation for an application using this and the           │
│     MCP2515 SPI Engine for experimentation with CAN and the Parallax Propeller.             │
│                                                                                             │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│ This example is of a traffic handler which coordinates requests to send packets             │
│ via the CAN interface and it handles the arrival of packets from the CAN interface.         │
│ This traffic handler runs in its own Cog but can be conceptialized as two handlers          │
│ one for outbound traffic and the other for inbound.                                         │
│ These are responsible for managing the packet traffic to/from the attached MCP2515 CAN      │
│ Controller. They invoke the MCP2515 SPI Engine which runs in its own Cog.                   │
│                                                                                             │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   The hardware for the Transmit-side of the traffic handler appears to be:                  │
│    ┌──────────────────┐       ┌────────────┐                                                │
│    │ Propeller        │       │ MCP 2515   │                                                │
│    │                  │       │            │                                                │
│    │        cmds/data ├┤ cmds/data  │                                                │
│    │    CAN Interrupt │←──────┤ /INT       │                                                │
│    └──────────────────┘       └────────────┘                                                │
│ The transmit traffic handler recives a packet to be transmitted at its input queue. It      │
│ then waits for the transmitter to become ready to do another transmit and then sends the    │
│ packet to the 2515 for transmission. When the transmit has completed the /INT line will     │
│ indicate that the completion status is now available. The transmit handler then gathers     │
│ the status from the 2515 and counts the transmission as successful or records an error.     │
│ In either case, the transmitter can now attempt to send another packet if one has           │
│ arrived in the input queue.                                                                 │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   The hardware for the Receive-side of the traffic handler appears to be:                   │
│    ┌──────────────────┐       ┌────────────┐                                                │
│    │ Propeller        │       │ MCP 2515   │                                                │
│    │                  │       │            │                                                │
│    │        cmds/data ├┤ cmds/data  │                                                │
│    │ CAN Rx0 Bfr Full │←──────┤ /Rx0BF     │                                                │
│    │ CAN Rx1 Bfr Full │←──────┤ /Rx1BF     │                                                │
│    └──────────────────┘       └────────────┘                                                │
│ The receive handler waits for either of the buffer full lines to indicate that a packet has │
│ arrived when one so says, it then reads the packet from the appropriate buffer in the 2515  │
│ and places it in the output queue. The act of reading from the buffer clears the signal     │
│ and the buffer so they are now ready to recieve another packet from the CAN bus.            │
│ At each receipt the receive status is checked and the receive is counted as good or flawed. │
│                                                                                             │
│ NOTE: What appears in these diagrams as a bidirectional cmd/data bus is provided by         │
│ interaction with our MCP2515-SPI Engine which serves as the hardware access for cmds/data   │
│ by this traffic handler.                                                                    │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ Revision History                                                                            │
│                                                                                             │
│ v1.0  created by Stephen Moraco                                                             │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


The MicroChip page for the MCP 2515 Stand-alone CAN Controller
 http://www.microchip.com/stellent/idcplg?IdcService=SS_GET_PAGE&nodeId=1335&dDocName=en010406

The MCP 2551 CAN Transceiver page:
 http://www.microchip.com/stellent/idcplg?IdcService=SS_GET_PAGE&nodeId=1335&dDocName=en010405

 
 }}

{
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Logic for CAN transmission/reception                                                        │
├────────────┬────────────────────────────────────────────────────────────────────────────────┤
│  Transmit  │                                                                                │
├────────────┘                                                                                │
│ (t1) Single buffer transmit routine only (use tx0, Tx[1,2] ignored)                         │
│ (t2) /INT signals when transmit has completed and we can send another                       │
│ (t3) We clear interrupt by clearing or simply loading another                               │
│ DATA                                                                                        │
│ (t4) We have an in-queue for outgoing packets (MCP 14byte format)                           │
│ (t5) We maintain count of TxMsgs and we allow clear of this count                           │
├────────────┬────────────────────────────────────────────────────────────────────────────────┤
│  Receive   │                                                                                │
├────────────┘                                                                                │
│ (r1) Receive into two receive buffers [0,1]                                                 │
│ (r2) /Rx0BF and /Rx1BF lines signal when we need to upload received                         │
│       message from either buffer                                                            │
│ DATA                                                                                        │
│ (r3) We have an out-queue for incoming packets (MCP 14byte format)                          │
│ (r4) We maintain count of RxMsgs and we allow clear of this count                           │
├────────────┬────────────────────────────────────────────────────────────────────────────────┤
│  Errors    │                                                                                │
├────────────┘                                                                                │
│ (e1) /INT signals if error has occurred                                                     │
│ (e2) We gather status and then clear interrupt                                              │
│ DATA                                                                                        │
│ (e3) We maintain current status so Command-Interpreter sends it as                          │
│       needed                                                                                │
│ (e4) We maintain counts of errors and we allow clear of these counts                        │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
}

CON
  #0,MODE_LOOPBACK, MODE_READONLY, MODE_READWRITE       ' input parameter values
  
  #1,LINE_INT,#2,LINE_RX0BF,#4,LINE_RX1BF               ' bit mask values

  #0,RXS_NOTHING_READY, RXS_STILL_MORE, RXS_NO_MORE     ' return values

  NBR_LONGS_RX_STACK = 128


VAR
  ' control lines: outputs to MCP2515
  byte  m_pinCAN_RESETb, m_pinCAN_CSb

  ' status lines: inputs from MCP2515
  byte  m_pinCAN_INTb, m_pinCAN_Rx0BFb, m_pinCAN_Rx1BFb

  ' SPI interface lines
  byte m_pinSPI_Rx, m_pinSPI_Tx, m_pinSPI_Clk


  byte  m_bStarted, m_bTesting

  long m_nRxHandlerCog

  long  m_nRxStack[NBR_LONGS_RX_STACK]

  byte m_bTxIsBusy

  long  m_nCountReceives                               ' 8 consecutive longs!!!!
  long  m_nCountReceiveErrors
  long  m_nCountReceiveOverflows
  long  m_nCountTransmits
  long  m_nCountTransmitErrors
  long  m_nCountMessageErrors
  long  m_nCountMultiSourceErrs
  long  m_nCountWakeErrors

  byte m_nPriorMcpErrFlags

  long  m_nTempEntryBffr[TxQue#ENTRY_SIZE_IN_LONGS]     ' our local 4-long (16-byte entry)

  long m_pEntryBffr                                     ' so we can debug


OBJ
  SPI           : "MCP2515-SPI Engine"
  TxQue         : "Queue"
  RxQue         : "Queue"

PUB Start(pinCAN_RESETb_p, pinCAN_CSb_p, pinCAN_INTb_p, pinCAN_Rx0BFb_p, pinCAN_Rx1BFb_p, pinSPI_Rx_p, pinSPI_Tx_p, pinSPI_Clk_p) : okay

'' Assign pins to CAN/SPI systems
  m_pinCAN_RESETb := pinCAN_RESETb_p
  m_pinCAN_CSb    := pinCAN_CSb_p
  m_pinCAN_INTb   := pinCAN_INTb_p
  m_pinCAN_Rx0BFb := pinCAN_Rx0BFb_p
  m_pinCAN_Rx1BFb := pinCAN_Rx1BFb_p

  m_pinSPI_Rx     := pinSPI_Rx_p
  m_pinSPI_Tx     := pinSPI_Tx_p
  m_pinSPI_Clk    := pinSPI_Clk_p

'' Init status pin direction
  dira[m_pinCAN_INTb]~                                  ' Set pin to input
  dira[m_pinCAN_Rx0BFb]~                                ' Set pin to input
  dira[m_pinCAN_Rx1BFb]~                                ' Set pin to input
  ' NOTE: remaining pins setup by MCP2551 SPI Engine

  Init                                                  ' reset the MCP 2515

PUB GetTxBufferPtr : pBffr                                                      '' (DBG) get buffer pointer for display

     pBffr := @m_nTempEntryBffr


CON                                                     ' Setup/Configuration values for MCP2515
  RX0BFS_BIT_MASK = $10
  RX1BFS_BIT_MASK = $20
  WAKE_ERROR_INTR_BIT_MASK = $40


PRI Init                                                                        ' INTERNAL setup MCP2515 for initial use

  ' -------------------------------
  ' ENABLE one of the following
  m_bTesting := FALSE
  'm_bTesting := TRUE
  ' -------------------------------

  TxQue.Init                                            ' initialize our Transmit Queue for use
  RxQue.Init                                            ' initialize our Receive Queue for use

  m_bTxIsBusy := FALSE
  m_nPriorMcpErrFlags := 0

'' start the SPI system
  SPI.Start(m_pinCAN_RESETb, m_pinCAN_CSb, m_pinSPI_Rx, m_pinSPI_Tx, m_pinSPI_Clk, 20_000_000, SPI#USE_RESET_LINE)

'' Send 1st SPI command to initiate SPI handler
  if CanSetMode(SPI#MODE_CONFIG)
    m_bStarted~~                                          ' flag MCP255 handler as STARTED

  if m_bStarted & m_bTesting
  ' TEST TEST TEST  ---- Hardware turn-on/verification
  '   configure Rx[01]BF for General I/O
  '   trigger interrupt, set Rx0BF then Rx1BF so we can see all three events
  '   on analyzer so we can prove all three lines are working...

  ' NOTE for production: our POWER-ON self test can do this to ensure our lines are
  '    still working!
    SPI.WriteRegister(SPI#REG_TXRTSCTRL, $00)                ' make Tx[0-2]RTS simple digital inputs (not used)
    ' TEST make our Rx[01]BF digitial outputs
    SPI.WriteRegister(SPI#REG_BFPCTRL, $0C)                  ' use $0F for normal operation
    SPI.WriteRegister(SPI#REG_RXB0CTRL, $24)                 ' set for only StdID Packets and allow roll-over to rx1BF
    SPI.WriteRegister(SPI#REG_RXB1CTRL, $20)                 ' set for only StdID Packets
    ' TEST turn on Rx0BF bit
    SPI.BitModifyRegister(SPI#REG_BFPCTRL, RX0BFS_BIT_MASK, RX0BFS_BIT_MASK)
    ' TEST and back off again
    SPI.BitModifyRegister(SPI#REG_BFPCTRL, RX0BFS_BIT_MASK, 0)
    ' TEST turn on Rx1BF bit
    SPI.BitModifyRegister(SPI#REG_BFPCTRL, RX1BFS_BIT_MASK, RX1BFS_BIT_MASK)
    ' TEST and back off again
    SPI.BitModifyRegister(SPI#REG_BFPCTRL, RX1BFS_BIT_MASK, 0)
    ' TEST leave both bits on (so lines look de-asserted)
    SPI.BitModifyRegister(SPI#REG_BFPCTRL, RX0BFS_BIT_MASK|RX1BFS_BIT_MASK, RX0BFS_BIT_MASK|RX1BFS_BIT_MASK)
    ' TEST enable interrupt
    SPI.BitModifyRegister(SPI#REG_CANINTE, WAKE_ERROR_INTR_BIT_MASK, WAKE_ERROR_INTR_BIT_MASK)
    ' TEST assert interrupt
    SPI.BitModifyRegister(SPI#REG_CANINTF, WAKE_ERROR_INTR_BIT_MASK, WAKE_ERROR_INTR_BIT_MASK)
    ' TEST and deassert
    SPI.BitModifyRegister(SPI#REG_CANINTF, WAKE_ERROR_INTR_BIT_MASK, 0)
     ' TEST and disable interrupt
    SPI.BitModifyRegister(SPI#REG_CANINTE, WAKE_ERROR_INTR_BIT_MASK, 0)
    ' now transition to loopback mode (no effect on CAN bus) for testing...
    ' CanSetMode(SPI#MODE_LOOPBACK)

  elseif m_bStarted

    SPI.WriteRegister(SPI#REG_TXRTSCTRL, $00)                ' make Tx[0-2]RTS simple digital inputs (not used)
    ' Make our Rx[01]BF interrupt requests
    SPI.WriteRegister(SPI#REG_BFPCTRL, $0F)                  ' use $0C for test operation
    SPI.WriteRegister(SPI#REG_RXB0CTRL, $24)                 ' set for only StdID Packets and allow roll-over to rx1BF
    SPI.WriteRegister(SPI#REG_RXB1CTRL, $20)                 ' set for only StdID Packets
    SPI.WriteRegister(SPI#REG_CANINTF, $00)                  ' Clear any pending interrupts
    SPI.WriteRegister(SPI#REG_CANINTE, $BC)                  ' Enable only $80 MsgErr, $20 ErrInt, and $1c Tx[0-2]IE bits
    ' our command interface should direct any further setup/changes... we're done...

    ' and let's start our receiver/transmitter
    m_nRxHandlerCog := cognew(CANreceiveHandler, @m_nRxStack) + 1


PUB ClearCounters                                                               '' (USER) clear (reset to 0) the counters

'' Clear all CAN transport counters (reset 'em to zero)

  m_nCountReceives := 0
  m_nCountReceiveErrors := 0
  m_nCountReceiveOverflows := 0
  m_nCountTransmits := 0
  m_nCountTransmitErrors := 0
  m_nCountMessageErrors := 0
  m_nCountMultiSourceErrs := 0
  m_nCountWakeErrors := 0


PUB GetCounters(pBffr_p)                                                        '' (USER) retrieve the current counter values

'' return 8-longs (all counters) to user's buffer [#rx,#rxErr,#rxOvflw,#tx,#txErr,#msgErr,#multiErr,#wakeErr]

  longMove(pBffr_p, @m_nCountReceives, 8)


PUB OpenChannel(nOpenMode_p)                                                    '' (USER) open the CAN channel in one of couple of modes

{{Open for Reading, Lurking, or ReadWrite - let the CAN traffic flow!}}

  case nOpenMode_p
    MODE_LOOPBACK:
      CanSetMode(SPI#MODE_LOOPBACK)
    MODE_READONLY:
      CanSetMode(SPI#MODE_LISTEN)
    MODE_READWRITE:
      CanSetMode(SPI#MODE_NORMAL)
   OTHER:
      CanSetMode(SPI#MODE_CONFIG)


PUB CloseChannel                                                                '' (USER) close the CAN channel

'' Close - we no longer receive CAN traffic!

  CanSetMode(SPI#MODE_CONFIG)

PUB WakeChannel

'' Set the wake interrupt bit in correct register to "generate" interrupt wakeup
  SPI.BitModifyRegister(SPI#REG_CANINTF, WAKE_ERROR_INTR_BIT_MASK, WAKE_ERROR_INTR_BIT_MASK)

PUB SleepChannel

'' Put the CAN transmitter into sleep mode

  CanSetMode(SPI#MODE_SLEEP)

PUB SetCanRate(nSpeed_p)                                                        '' (USER) set one of 7 built-in CAN bit-rates

'' Set desired CAN bps to value assoc with [0-8]

  case nSpeed_p
    0: ' 10Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $E7)
      SPI.WriteRegister(SPI#REG_CNF2, $FC)
      SPI.WriteRegister(SPI#REG_CNF3, $05)
    1: ' 20Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $A7)
      SPI.WriteRegister(SPI#REG_CNF2, $D2)
      SPI.WriteRegister(SPI#REG_CNF3, $02)
    2: ' 50Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $8F)
      SPI.WriteRegister(SPI#REG_CNF2, $D2)
      SPI.WriteRegister(SPI#REG_CNF3, $02)
    3: ' 100Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $87)
      SPI.WriteRegister(SPI#REG_CNF2, $D2)
      SPI.WriteRegister(SPI#REG_CNF3, $02)
    4: ' 125Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $47)
      SPI.WriteRegister(SPI#REG_CNF2, $CA)
      SPI.WriteRegister(SPI#REG_CNF3, $01)
    5: ' 250Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $43)
      SPI.WriteRegister(SPI#REG_CNF2, $D1)
      SPI.WriteRegister(SPI#REG_CNF3, $01)
    6: ' 500Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $41)
      SPI.WriteRegister(SPI#REG_CNF2, $CA)
      SPI.WriteRegister(SPI#REG_CNF3, $01)
    7: ' 800Kbps
      SPI.WriteRegister(SPI#REG_CNF1, $80)
      SPI.WriteRegister(SPI#REG_CNF2, $D2)
      SPI.WriteRegister(SPI#REG_CNF3, $02)
    8: ' 1Mbps
      SPI.WriteRegister(SPI#REG_CNF1, $40)
      SPI.WriteRegister(SPI#REG_CNF2, $CA)
      SPI.WriteRegister(SPI#REG_CNF3, $01)
    OTHER:
      ' nothing done in this case


PUB ReadRegister(nRegAddr_p) : nRegValue                                        '' (DBG) allow direct read of MCP2515 register

'' read specified MCP 2515 register [00-7F] and return its value

  nRegValue := SPI.ReadRegister(nRegAddr_p)


PUB WriteRegister(nRegAddr_p, nRegValue_p)                                      '' (DBG) allow direct write of MCP2515 register

'' write value to specified MCP 2515 register [00-7F]

  SPI.WriteRegister(nRegAddr_p, nRegValue_p)


PUB ModifyRegisterBits(nRegAddr_p, nRegBitMask_p, nRegBitValue_p)               '' (DBG) allow direct bit-modify of MCP2515 register bits

'' modify specific bits in bit-modifiable register

  SPI.BitModifyRegister(nRegAddr_p, nRegBitMask_p, nRegBitValue_p)


PUB SendPacket(nMsgId_p, nNbrBytes_p, pBffr_p) | pEntryBffr, nIdx               '' (USER) send packet via CAN

'' enqueue packet for transmission via CAN

' get next Tx queue entry (16-bytes) and populate it with MCP 13-byte
' buffer (last 3 bytes not used)
'
' NOTE: this is a two stage queue in that we get an entry and then
'       we mark it filled and ready for processing (after we fill it ;-)

  ' build our packet into an MCP formatted buffer
  Fmt2Mcp(@m_nTempEntryBffr, nMsgId_p, nNbrBytes_p, pBffr_p)

  ' wait for an entry to become usable
  repeat until TxQue.IsNextEntryEmpty

  ' get the entry recording it onto our Tx queue
  pEntryBffr := TxQue.AllocEntry

  ' copy our build image to queue buffer
  longMove(pEntryBffr, @m_nTempEntryBffr, TxQue#ENTRY_SIZE_IN_LONGS)

  ' now mark it as filled and ready for processing
  TxQue.MarkEntryFilled(pEntryBffr)


PRI Fmt2Mcp(pDestBffr, nMsgId_p, nNbrBytes_p, pBffr_p) | nIdx           ' CONVERT raw to MCP format
  ' !!DEBUG TESTED!!

  ' fill our entry being built, first with zeros
  longfill(pDestBffr, 0, TxQue#ENTRY_SIZE_IN_LONGS)

  ' fill in Msg Id
  byte [pDestBffr][0] := (nMsgId_p >> 3) & $ff
  byte [pDestBffr][1] := (nMsgId_p & $07) << 5

  ' fill in payload length
  byte [pDestBffr][4] := nNbrBytes_p

  ' if we have payload bytes copy them
  if nNbrBytes_p > 0
    repeat nIdx from 0 to nNbrBytes_p - 1
      byte [pDestBffr][5+nIdx] := byte [pBffr_p][nIdx]



PUB IsReceiveQueueEmpty : bQueueStatus                                          '' SPECIAL allow outside to look at state of Rx queue

'' Return T/F where T means there are no received packets in the Receive Queue

   bQueueStatus := RxQue.IsEmpty


PUB ReceivePacket(pDestBffr_p) : nRcvStatus | pEntryBffr

{{
 Retrieve a queued received message if there is one and
 format it (binary) into the callers buffer as follows:

    LONG1 msgId (11 or 29-bits valid) - BIT30=1 when is 29-bit ID
    --
    LONG2.word[0] - empty
    LONG2.byte[2] - empty
    LONG2.byte[3] - payload length
    --
    LONG3.byte[0] - payload[0]
    LONG3.byte[1] - payload[1]
    LONG3.byte[2] - payload[2]
    LONG3.byte[3] - payload[3]
    --
    LONG4.byte[0] - payload[4]
    LONG4.byte[1] - payload[5]
    LONG4.byte[2] - payload[6]
    LONG4.byte[3] - payload[7]

 RETURNs:
   MCP2515#RXS_NOTHING_READY - there is nothing recevied
   MCP2515#RXS_NO_MORE       - here's packet and no more waiting
   MCP2515#RXS_STILL_MORE    - here's packet and there are more waiting
}}

  nRcvStatus := RXS_NOTHING_READY

  if NOT RxQue.IsEmpty and RxQue.IsNextEntryFilled

     ' now get the entry and let's send it!
    pEntryBffr := RxQue.PopEntry

    ' and reformat our buffer for caller
    Fmt2intrnl(pDestBffr_p, pEntryBffr)

    ' mark queue data empty (we've emptied this entry)
    RxQue.MarkEntryEmpty(pEntryBffr)

    ' and tell our caller if this is more or not
    if RxQue.IsEmpty
      nRcvStatus := RXS_NO_MORE
    else
      nRcvStatus := RXS_STILL_MORE
      

PRI Fmt2intrnl(pDestBffr, pSrcBffr) | nIdx, nNbrBytes, nMsgId, nPayLen  ' CONVERT MCP format to INTERNAL format
  ' !!DEBUG TESTED!!

  ' fill our entry being built, first with zeros
  longfill(pDestBffr, 0, TxQue#ENTRY_SIZE_IN_LONGS)

  ' gather MsgId
  nMsgId := byte [pSrcBffr][0] << 3
  nMsgId |= (byte [pSrcBffr][1] >> 5) & $07
  bytemove(pDestBffr, @nMsgId, 4)

  ' gather payload length
  nNbrBytes := byte [pSrcBffr][4] <# 8                   ' 8 bytes max!
  nPayLen := 0
  nPayLen.word[0] := -1         ' simulate Time-Stamp
  nPayLen.byte[3] := nNbrBytes
  bytemove(@byte [pDestBffr][4], @nPayLen, 4)

  ' if we have payload bytes copy them
  if nNbrBytes > 0
    repeat nIdx from 0 to nNbrBytes - 1
      byte [pDestBffr][8+nIdx] := byte [pSrcBffr][5+nIdx]


PUB Stop                                                                        '' (USER) Stop the CAN backend system

'' Stop the SPI back-end and packet traffic handler

    if m_nRxHandlerCog
       cogstop(m_nRxHandlerCog~ - 1)

    if m_bStarted
      SPI.Stop
      m_bStarted~                                         ' flag MCP255 handler as STOPPED


PUB GetInterruptStatuses : nLineStatus                                          '' (DBG) retrieve line state so can display

'' Return the summary of the 3 interrupting lines
''  See MASK bits in this files' header

'' NOTE: this call inverts the values to TRUE logic
''  meaning that a bit asserted will be shown in the
''  value as 1!  (even tho' this interface is active low)

  nLineStatus := 0

  if ina[m_pinCAN_INTb]
  else
    nLineStatus |= LINE_INT
  if ina[m_pinCAN_Rx0BFb]
  else
    nLineStatus |= LINE_RX0BF
  if ina[m_pinCAN_Rx1BFb]
  else
    nLineStatus |= LINE_RX1BF


'----------------------------------------------------------------------------------------------
CON                                                     ' Simple mode masks and retry counts for changing state of MCP2515
  MODE_BITS_MASK = $E0
  MAX_CONFIG_SET_TRIES = 2
  MAX_VERIFY_TRIES = 5


PRI CanSetMode(newModeValue) : okay | nDesiredValue, initReadLoopCt, initWriteLoopCt

  initReadLoopCt := MAX_VERIFY_TRIES
  initWriteLoopCt := MAX_CONFIG_SET_TRIES

  nDesiredValue := newModeValue & MODE_BITS_MASK

  CanWriteMode(newModeValue)
  repeat while CanGetMode <> nDesiredValue
    initReadLoopCt--
    if initReadLoopCt == 0
      CanWriteMode(newModeValue)
      initReadLoopCt := MAX_VERIFY_TRIES
      initWriteLoopCt--
      if initWriteLoopCt == 0
        return FALSE

  return TRUE


PRI CanWriteMode(newModeValue)

  SPI.BitModifyRegister(SPI#REG_CANCTRL, MODE_BITS_MASK, newModeValue)

  
PRI CanGetMode : currModeValue

  currModeValue := SPI.ReadRegister(SPI#REG_CANSTAT) & MODE_BITS_MASK


'==============================================================================================
PRI CANreceiveHandler                                   ' COG: receive Handler (/Rx[01]BF and /INT lines and do Transmit, too)

' wait for either of our  Rx[0|1]BF_pin's to go asserted then
' unload and queue the associated buffer
' if our /INT line is asserted then handle it, too

  repeat
    if ina[m_pinCAN_Rx0BFb] == 0
      GetAndQueueBuffer(0)

    if ina[m_pinCAN_Rx1BFb] == 0
      GetAndQueueBuffer(1)

    if ina[m_pinCAN_INTb] == 0
      CheckAndHandleINTline

    ' Process a pending send
    if NOT m_bTxIsBusy and NOT TxQue.IsEmpty
      SendNextQueuedPacket


PRI GetAndQueueBuffer(nBffrNbr_p) | nRdCmd

' unload and queue the specified buffer

  ' if room in queue...
  if NOT RxQue.IsFull

    ' wait for an entry to become usable
    repeat until RxQue.IsNextEntryEmpty

    ' get the entry recording it onto our Rx queue
    m_pEntryBffr := RxQue.AllocEntry

    ' have received data to be read via SPI, so let's go get it
    nRdCmd := SPI#CMD_RD_RXBFR_BASE | ((nBffrNbr_p & $01) << 2)
    SPI.UnloadRxBuffer(nRdCmd, m_pEntryBffr)

    ' mark queue data empty
    RxQue.MarkEntryFilled(m_pEntryBffr)

    ' count a receive
    m_nCountReceives++


PRI CheckAndHandleINTline | bWasTransmit, nMcpStatus, nMcpIntrFlags, nMcpErrFlags, nDiffMcpErrFlags

  ' handle our three interrupt lines here
    bWasTransmit := FALSE

  ' process /INT line notification
    ' have interrupt line due to (1) tx complete, (2)tx error, or (3) rx error
    ' clear appropriate interrupt lines

    ' read abbreviated status
    nMcpStatus := SPI.GetReadStatus

    ' did Tx0 transmit complete?
    if (nMcpStatus & SPI#BIT_RDSTATUS_TX0IF) <> 0
      ' yes- clear our transmitter busy flag
      m_bTxIsBusy := FALSE
      ' show this interrupt was due to a tranmit issue
      bWasTransmit := TRUE
      ' count a transmit
      m_nCountTransmits++
      ' clear our transmit complete flag
      ModifyRegisterBits(SPI#REG_CANINTF, SPI#BIT_INTF_TX0IF, 0)

    ' if still have a /INT notification, look for more causes
    if ina[m_pinCAN_INTb] == 0
      ' read interrupt status
      nMcpIntrFlags := ReadRegister(SPI#REG_CANINTF)

      ' did Tx0 transmit complete?
      if (nMcpIntrFlags & SPI#BIT_INTF_TX0IF) <> 0
        ' yes- clear our transmitter busy flag
        m_bTxIsBusy := FALSE
        ' show this interrupt was due to a tranmit issue
        bWasTransmit := TRUE
        ' count a transmit
        m_nCountTransmits++
        ' clear our transmit complete flag
        ModifyRegisterBits(SPI#REG_CANINTF, SPI#BIT_INTF_TX0IF, 0)

      ' Handle a Message Error
      if (nMcpIntrFlags & SPI#BIT_INTF_MERIF) <> 0
        ' count this error
        m_nCountMessageErrors++
        if bWasTransmit
           m_nCountTransmitErrors++
        else
           m_nCountReceiveErrors++
        ' clear our message error flag
        ModifyRegisterBits(SPI#REG_CANINTF, SPI#BIT_INTF_MERIF, 0)

      ' Handle a Multiple Source Error
      if (nMcpIntrFlags & SPI#BIT_INTF_ERRIF) <> 0
         ' count this multiple source error
         m_nCountMultiSourceErrs++
         nMcpErrFlags := ReadRegister(SPI#REG_EFLG)
         ' do we have a different value from last time?
         if m_nPriorMcpErrFlags <> nMcpErrFlags
           ' yes, idenitfy which bits changed?
           nDiffMcpErrFlags :=  nMcpErrFlags ^ m_nPriorMcpErrFlags

           if (nDiffMcpErrFlags & SPI#BIT_EFLG_RX0OVR) and  (nMcpErrFlags & SPI#BIT_EFLG_RX0OVR)
             m_nCountReceiveOverflows++

           if (nDiffMcpErrFlags & SPI#BIT_EFLG_RX1OVR) and  (nMcpErrFlags & SPI#BIT_EFLG_RX1OVR)
             m_nCountReceiveOverflows++
           ' record this time's bits for next time
           m_nPriorMcpErrFlags := nMcpErrFlags

        ' clear our multiple-source error flag
        ModifyRegisterBits(SPI#REG_CANINTF, SPI#BIT_INTF_ERRIF, 0)


PRI SendNextQueuedPacket | pEntryBffr

' dequeue and send a packet

  if NOT TxQue.IsEmpty
    ' process outbound packet
    if TxQue.IsNextEntryFilled

      ' now get the entry and let's send it!
      pEntryBffr := TxQue.PopEntry

      ' have data to be sent via SPI, so fill transmit buffer 0
      SPI.LoadTxBuffer(SPI#PARM_LD_TXBFR0_SIDH, @m_nTempEntryBffr)

      ' mark queue data empty
      TxQue.MarkEntryEmpty(pEntryBffr)

      ' request that TxBuffer0 be sent
      SPI.SendTxBuffer(SPI#CMD_RTS_TxBFR0)

      ' now mark transmitter busy
      m_bTxIsBusy := TRUE


'----------------------------------------------------------------------------------------------