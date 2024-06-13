; Test of SIO channel A in synchronous mode on an SC104 card
; Uses an ATTINY84A to generate the clocks and discrete signals
; 
; SIO_A DTR high->low tells the TINY84A to generate pre-transmission clocks
; SIO_A DTR low->high tells the TINY84A to generate post-transmission clocks
;
; Pulse SIO_A RTS low to tell the TINY84A to generate a block of 8 clocks
;
; NOTE: If there's a TX under-run - i.e. no data to TX when additional
;       clocks come along, SIO will output the byte in WR6.
;
; Assemble using the free online assembler at www.asm80.com
;

; SC129 Digital I/O module output 0 is used as the SPI device CS signal.
OUT_PORT    EQU     $00 ; SC129 output port address

; SC104 with no DIP switch fitted has a base address of $FC
; The 74HCT04 is NOT fitted so the ZILOG addressing mode is used
SIOA_D      EQU     $FC ; SIO-A Data
SIOA_C      EQU     $FE ; SIO-A Command/Status

            .ORG    $8000 

; set the test SPI device CS line HIGH
            LD      A,$01
            OUT     (OUT_PORT),A

; configure SIO channel A for synchronous serial with ext sync
            LD      A,$18       ; WR0 : channel reset
            OUT     (SIOA_C),A 

            LD      A,$10       ; WR0 : reset interrupts
            OUT     (SIOA_C),A 

            LD      A,$04       ; WR4 before other registers
            OUT     (SIOA_C),A 
            LD      A,$30       ; Sync mode + External sync
            OUT     (SIOA_C),A 

            ; this byte is output when there is a TX under-run
            LD      A,$06       ; WR6
            OUT     (SIOA_C),A 
            LD      A,$2A       ; Sync byte = $AA - comes out as $54
            OUT     (SIOA_C),A 

            ; TX: 8 bits/char - DON'T ENABLE THE TX
            LD      A,$05       ; WR5
            OUT     (SIOA_C),A 
            LD      A,$60       ; 8 bits/char
            OUT     (SIOA_C),A 

            ; RX: 8 bits/char - DON'T ENABLE THE RX
            LD      A,$03 ; WR3
            OUT     (SIOA_C),A 
            LD      A,$C2       ; 8 bits/char + Sync Char Inhibit
            OUT     (SIOA_C),A 

; delay a while
            CALL    DELAY200
            CALL    DELAY200
            CALL    CRLF
            CALL    CRLF
            
; ======= START OF MESSAGE ONE =======
; RD000004 - Read 4 bytes starting at address $0000 in the 25LC256

            ; print out the message to the console for info
            LD      HL,MSG_TX
            CALL    WRSTRZ
        
            LD      HL,RD000004
            LD      B,7
            CALL    WRBYTES
            CALL    CRLF

            ; do the actual SPI transfer
            LD      HL,RD000004
            LD      B,7
            CALL    SPI_XFER

            ; print out the returned bytes buffer
            LD      HL,MSG_RX
            CALL    WRSTRZ

            LD      HL,SPI_MSG
            LD      B,7
            CALL    WRBYTES
            CALL    CRLF
            CALL    CRLF
            
            CALL    DELAY15

; ======= START OF MESSAGE TWO =======
; RD01F404 - Read 8 bytes starting at address $01F4 in the 25LC256

            ; print out the message to the console for info
            LD      HL,MSG_TX
            CALL    WRSTRZ

            LD      HL,RD01F404
            LD      B,11
            CALL    WRBYTES
            CALL    CRLF

            ; do the actual SPI transfer
            LD      HL,RD01F404
            LD      B,11
            CALL    SPI_XFER

            ; print out the returned bytes buffer
            LD      HL,MSG_RX
            CALL    WRSTRZ

            LD      HL,SPI_MSG
            LD      B,11
            CALL    WRBYTES
            CALL    CRLF
            CALL    CRLF
            
; return to monitor
            RST     $28 

; SPI_XFER
; HL holds the pointer to the buffer to send
; B  holds the number of bytes to send
SPI_XFER:
            PUSH    BC
            PUSH    DE
            LD      DE,SPI_MSG            
            LD      C,$00       ; set Rx byte count to 0
            
            ; set SPI CS low (i.e. SC129 output bit 0)
            LD      A,$0
            OUT     (OUT_PORT),A 

            ; load 1st data byte to send
            LD      A,(HL)      ; read the 1 first byte from memory
            CALL    BIT_REV     ; flip the bit order
            OUT     (SIOA_D),A  ; load into the SIO TX register
            INC     HL          ; point to next Tx byte

            ; enable RX - 8 bits/char
            LD      A,$03 ; WR3
            OUT     (SIOA_C),A 
            LD      A,$C3       ; 8 bits/char + Sync Char Inhibit
            OUT     (SIOA_C),A 
            
            ; enable TX & set SIO_B DTR LOW to signal the UNO to start pre-transmission
            ; UNO will then generate 2 clock cycles for TxC
            LD      A,$05       ; WR5
            OUT     (SIOA_C),A 
            LD      A,$E8       ; DTR + Tx enable + 8 bits/char
            OUT     (SIOA_C),A 
            
            ; wait for pre-transmission to complete - i.e. CTS goes LOW
            CALL    WAIT_CTS

            ; signal the UNO to generate 8 clock cycles for the SIO & SPI device
            CALL    PULSE_RTS

            ; don't need to wait for tx to complete here as the SIO has already
            ; snatched the byte from the tx register so it's already empty
;            CALL    WAIT_TX     ; wait for SIO TX register to empty

            DEC     B           ; decrement byte count
            JR      Z,SPI_FINISH
            
SPI_LOOP:   ; TRANSMIT
            LD      A,(HL)      ; read the next byte from memory
            CALL    BIT_REV     ; flip the bit order
            OUT     (SIOA_D),A  ; load into the SIO TX register
            INC     HL          ; point to next Tx byte
            NOP
            CALL    PULSE_RTS
            CALL    WAIT_TX     ; wait for SIO TX register to empty

            ; RECEIVE CHECK
            IN      A,(SIOA_C)  ; RR0: Status byte D0=RX Byte Available
            BIT     0,A         ; Is Rx Byte Available flag set?
            JR      Z,SPI_NEXT  ; Jump if byte NOT available
            
            ; RECEIVE
            IN      A,(SIOA_D)  ; read the received byte
            CALL    BIT_REV     ; flip the bit order
            LD      (DE),A      ; save the byte
            INC     DE
            INC     C           ; inc Rx byte count
            
SPI_NEXT:
            DJNZ    SPI_LOOP    ; repeat for next byte   

            ; disable TX & DTR HIGH - tells UNO to do post-transmission
            LD      A,$05       ; WR5
            OUT     (SIOA_C),A 
            LD      A,$60       ; 8 bits/char
            OUT     (SIOA_C),A 

SPI_CLEANUP:
            ; transmission complete, just have to get the remaining received bytes out!

            ; RECEIVE CHECK
            IN      A,(SIOA_C)  ; RR0: Status byte D0=RX Byte Available
            BIT     0,A         ; Is Rx Byte Available flag set?
            JR      Z,SPI_CU2   ; Jump if byte NOT available
            
            ; RECEIVE
            IN      A,(SIOA_D)  ; read the received byte
            CALL    BIT_REV     ; flip the bit order
            LD      (DE),A      ; save the byte
            INC     DE
            INC     C           ; inc Rx byte count

SPI_CU2:
            ; check CTS
            LD      A,$10       ; Reset Ext/Status Interrupts
            OUT     (SIOA_C),A
            IN      A,(SIOA_C)  ; RR0: Status byte D5=CTS
            BIT     5,A         ; Is CTS flag clear?
            JR      NZ,SPI_CLEANUP  ; not yet set so go back and check Rx status 
            
SPI_FINISH:
            ; set SPI CS high (i.e. PIO PA0 pin)
            LD      A,$01
            OUT     (OUT_PORT),A 

SPI_END:
            ; disable Rx
            LD      A,$03       ; WR3
            OUT     (SIOA_C),A 
            LD      A,$C2       ; 8 bits/char + Sync Char Inhibit
            OUT     (SIOA_C),A 

            POP     DE
            pop     BC
            RET
            
; wait for the SIO TX buffer to empty
WAIT_TX:
            IN      A,(SIOA_C)  ; RR0: Status byte D2=TX Buff Empty
            BIT     2,A         ; Is Tx Buff Empty flag set?
            JR      Z,WAIT_TX   ; Not ready
            RET      

; wait for CTS to go LOW
WAIT_CTS:
            LD      A,$10       ; Reset Ext/Status Interrupts
            OUT     (SIOA_C),A
            
wcts1:      IN      A,(SIOA_C)  ; RR0: Status byte D5=CTS
            BIT     5,A         ; Is CTS flag set?
            JR      Z,WAIT_CTS  ; not yet set so wait
            RET

; pulse RTS LOW to tell the UNO to generate 8 clocks
PULSE_RTS:
            LD      A,$05       ; WR5
            OUT     (SIOA_C),A 
            LD      A,$EA       ; DTR + RTS + Tx enable + 8 bits/char
            OUT     (SIOA_C),A
            LD      A,$05       ; WR5
            OUT     (SIOA_C),A 
            LD      A,$E8       ; DTR + Tx enable + 8 bits/char
            OUT     (SIOA_C),A            
            RET
            
FLUSH_RX:
            IN      A,(SIOA_C)  ; RR0: Status byte D0=RX Byte
            BIT     0,A         ; Is Rx Byte Available flag set?
            RET     Z           ; Empty so return

            IN      A,(SIOA_D)  ; read the RX register
            JR      FLUSH_RX
; 
; reverse the bit position of value in A
; 
BIT_REV:             
            PUSH    BC 
            LD      B,8         ; 8 bits to reverse
            LD      C,A         ; copy A to C
BR1:                 
            RL      C           ; MSB to carry
            RR      A           ; carry to LSB
            DJNZ    BR1 
            POP     BC 
            RET      

; Simple delay - 200mS ish
DELAY200:
            PUSH    BC
            PUSH    DE
            LD      DE,200
            LD      C,$0A
            RST     $30
            POP     DE
            POP     BC
            RET      

; Simple delay - 100mS ish
DELAY100:            
            PUSH    BC
            PUSH    DE
            LD      DE,100
            LD      C,$0A
            RST     $30
            POP     DE
            POP     BC
            RET      

; Simple delay - 50mS ish
            PUSH    BC
            PUSH    DE
            LD      DE,50
            LD      C,$0A
            RST     $30
            POP     DE
            POP     BC
            RET      

; Simple delay - 15mS ish
DELAY15:
            PUSH    BC
            PUSH    DE
            LD      DE,15
            LD      C,$0A
            RST     $30
            POP     DE
            POP     BC
            RET      
; 
; Write character to console using the SCM API function $02
; Character is in A
; The API call may affect all registers so save them first
PUTC:       PUSH    HL
            PUSH    DE
            PUSH    BC
            LD      C,$02
            RST     $30
            POP     BC
            POP     DE
            POP     HL
            RET
     
;
; Output a CR & LF
CRLF:       LD      A,10
            CALL    PUTC
            LD      A,13
            CALL    PUTC
            RET

;
; Write multiple bytes
; HL holds the first byte & B holds the number of bytes to print
;
WRBYTES:    LD      A,(HL)
            INC     HL
            CALL    WRBYTE
            LD      A,32
            CALL    PUTC
            DJNZ    WRBYTES
            RET
; 
; 
; Write 16-bit value to the console in HEX
; HL holds the 16-bit value
; 
WRADDR:              
            LD      A,H         ; Get HIGH byte
            CALL    WRBYTE      ; write byte
            LD      A,L         ; Get LOW byte
; 
; Write a byte to the console in HEX
; A holds the byte to write
; WRBYTE must follow WRADDR
; 
WRBYTE:              
            PUSH    AF          ; Save ACC
            RR      A           ; Shift upper nibble into
            RR      A           ; lower nibble
            RR      A 
            RR      A 
            CALL    WRNIB       ; Output high nibble
            POP     AF          ; Restore ACC
; 
; Write nibble to console in HEX
; A holds the nibble in bits 0..3
; WRNIB must follow WRBYTE
; 
WRNIB:               
            PUSH    AF          ; Save ACC
            AND     %00001111   ; Mask high nibble
            CP      $0A         ; Is it less than 10 decimal?
            JR      C,wrnib1    ; If less than 10, skip add 7
            ADD     A,7         ; Adjust for 10..15
WRNIB1:              
            ADD     A,"0"       ; Convert to printable
            CALL    PUTC        ; Output
            POP     AF          ; Restore ACC
            RET      

;
; Write null terminated string to the console
; HL holds address of the first character  
;
WRSTRZ:
        LD      A,(HL)      ; Get character
        INC     HL          ; inc HL to next char
        AND     A           ; is char NULL?
        RET     Z           ; return if NULL
        CALL	PUTC		; output the char
        JR      WRSTRZ      ; and repeat

MSG_TX:     DB      'TX: ',0
MSG_RX:     DB      'RX: ',0

; 
; RD000004 - Read 4 bytes starting at address $0000 in the 25LC256
RD000004:   DB      $03         ; the READ instruction
            DB      $00,$00     ; start address
            DB      0,0,0,0     ; NULL Bytes to get the data back
        
; 
; RD01F404 - Read 8 bytes starting at address $01F4 in the 25LC256
RD01F404:   DB      $03         ; the READ instruction
            DB      $01,$F4     ; start address
            DB      0,0,0,0     ; NULL Bytes to get the data back   
            DB      0,0,0,0     ; NULL Bytes to get the data back   

SPI_MSG:    DB      64 DUP ($00)
