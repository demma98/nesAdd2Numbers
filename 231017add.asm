	;registers
PPUCTRL		=	$2000
PPUMASK 	=	$2001
PPUSTATUS	=	$2002
OAMADDR		=	$2003
OAMDATA		=	$2004
PPUSCROLL	=	$2005
PPUADDR 	=	$2006
PPUDATA 	=	$2007
CONTROLLER_1	=	$4016

	;my registers
INPUT	=	$00
INPUT_TEMP	=	INPUT + $00
INPUT_1	=	INPUT + $01

CURSOR	=	$10
CURSOR_TEMP	=	CURSOR + $00
CURSOR_CLOCK	=	CURSOR + $01
CURSOR_BLINK	=	CURSOR + $02
CURSOR_PRESSED	=	CURSOR + $03

SCREEN_VARS	=	$30
SCREEN_TEMP	=	SCREEN_VARS + $00
SCROLL_X	=	SCREEN_VARS + $01
SCROLL_Y	=	SCREEN_VARS + $02
SCREEN_CLOCK	=	SCREEN_VARS + $03
SCREEN_MASK	=	SCREEN_VARS + $04
SCREEN_CTRL	=	SCREEN_VARS + $05

SCREEN		=	$40		

ENTITY		=	$60		
ENTITY_ID	=	ENTITY + $00	;ids
ENTITY_X	=	ENTITY + $10
ENTITY_Y	=	ENTITY + $20


.segment "HEADER"
  ; .byte "NES", $1A      ; iNES header identifier
  .byte $4E, $45, $53, $1A
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte $01, $00        ; mapper 0, vertical mirroring

.segment "VECTORS"
  ;; When an NMI happens (once per frame if enabled) the label nmi:
  .addr nmi
  ;; When the processor first turns on or is reset, it will jump to the label reset:
  .addr reset
  ;; External interrupt IRQ (unused)
  .addr 0

; "nes" linker config requires a STARTUP section, even if it's empty
.segment "STARTUP"

; Main code segement for the program
.segment "CODE"

reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs		;  .
  inx		; now X = 0
  stx $2000	; disable NMI
  stx $2001 	; disable rendering
  stx $4010 	; disable DMC IRQs

;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit PPUSTATUS
  bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory

;; second wait for vblank, PPU is ready after this
vblankwait2:
  bit PPUSTATUS
  bpl vblankwait2

main:
load_palettes:
  lda PPUSTATUS
  lda #$3f
  sta PPUADDR
  lda #$00
  sta PPUADDR
  ldx #$00
@loop:
  lda palettes, x
  sta PPUDATA
  inx
  cpx #$20
  bne @loop

enable_rendering:
  lda #%10000101	; Enable NMI
  sta PPUCTRL
  sta SCREEN_CTRL
  lda #%00011000	; Enable Sprites and background
  sta PPUMASK
  sta SCREEN_MASK

set_cursor:
  lda #$00
  sta OAMADDR
  lda #$01
  sta OAMADDR
  lda #$0a
  sta OAMDATA
  lda #$a0
  sta ENTITY_Y

set_scroll:
  lda #$e0
  sta SCROLL_X
  lda #$d0
  sta SCROLL_Y

set_screen:
  lda #$01
  ldx #$05		;primera fila
  @loop_set_screen_upper:	;poner 0s en la pantalla
  dex
  sta SCREEN, x
  cpx #$00
  bne @loop_set_screen_upper

  ldx #$02
  lda #$11
  sta SCREEN, x		;poner signo + enmedio

  lda #$12
  ldx #$05		;segunda fila
  @loop_set_screen_lower:	;poner 0s en la pantalla
  dex
  sta SCREEN + $10, x
  cpx #$00
  bne @loop_set_screen_lower

  ldx #$00
  lda #$16
  sta SCREEN + $10, x		;poner signo = al inicio


frame_loop:


  jmp frame_loop

nmi:
  lda PPUSTATUS

  lda #$3f		;1st sprite palette 2nd color
  sta PPUADDR
  lda #$11
  sta PPUADDR

  ldx CURSOR_BLINK
  lda palettes, x	;replace palette for blink effect
  sta PPUDATA		;replace color

  lda #$00		;update sprites
  sta OAMADDR
  sta OAMADDR
  ldx #$00
  @update_sprites:
  lda ENTITY_Y, x
  clc
  sbc SCROLL_Y
  adc #$47
  sta OAMDATA		;sprite y position
  ldy ENTITY_ID, x
  lda sprites_id, y
  sta OAMDATA		;sprite pattern
  lda sprites_config, y
  sta OAMDATA		;sprite attributes
  lda ENTITY_X, x
  clc
  sbc SCROLL_X
  sta OAMDATA		;sprite x position

  dex
  cpx #$ff
  bne @update_sprites
  

  lda #$20		;renderizar caracteres en pantalla
  sta PPUADDR
  lda SCREEN_CLOCK
  tax
  sta PPUADDR
  lda SCREEN, x
  sta PPUDATA		;cambiar los sprites en el fondo
  tay
  txa
  clc
  adc #$10		;moverse hacia abajo
  tax
  tya
  lda SCREEN, x
  sta PPUDATA

  lda SCROLL_X		;set screen fine scroll
  sta PPUSCROLL
  lda SCROLL_Y
  sta PPUSCROLL

  lda SCREEN_CTRL	;reestablecer las variables importantes de la ppu
  sta PPUCTRL
  lda SCREEN_MASK
  sta PPUMASK

	;END OF RENDERING

  inc CURSOR_CLOCK

  lda SCREEN_CLOCK
  clc
  adc #$01
  cmp #$05
  bne @skip_screen_clock_reset		;ignorar si el reloj no ha alcanzado el maximo
  lda #$00
  @skip_screen_clock_reset:
  sta SCREEN_CLOCK

controller:
  lda #$01	;setup controller 1
  sta CONTROLLER_1
  sta INPUT_1
  lsr A
  sta CONTROLLER_1
  @controller_1_read:
  lda CONTROLLER_1
  lsr A
  rol INPUT_1
  bcc @controller_1_read	;bucle con carry
  lda INPUT_1
  sta INPUT_TEMP		;guardar resultado para verlo mejor

cursor_move:
  lda CURSOR_PRESSED
  cmp #$00
  bne @skip_move_1		;si el boton sigue presionado se ignora todo


  lda INPUT_1
  and #%00000001
  cmp #%00000001
  bne @skip_right		;ignorar si el boton derecho no està presionado
  lda ENTITY_X
  cmp #$20			;ignorar si esta en borde derecho
  beq @skip_right
  clc
  adc #$08			;mover a la derecha 1 casilla
  sta ENTITY_X
  inc CURSOR_PRESSED		;indicar tecla presionada
  cmp #$10
  bne @skip_right		;ignorar si no esta en la celda 2
  clc
  adc #$08
  sta ENTITY_X
  @skip_right:

  jmp @skip_skip_move_1		;no me deja hacer el salto completo
  @skip_move_1:
  jmp @skip_move_2
  @skip_skip_move_1:


  lda INPUT_1
  and #%00000010
  cmp #%00000010
  bne @skip_left		;ignorar si el boton izquierdo no està presionado
  lda ENTITY_X
  cmp #$00
  beq @skip_left		;ignorar si esta en borde izquierdo
  clc
  sbc #$07			;mover a la izquierda 1 casilla
  sta ENTITY_X
  inc CURSOR_PRESSED		;indicar tecla presionada
  cmp #$10
  bne @skip_left		;ignorar si no esta en la celda 2
  clc
  sbc #$07
  sta ENTITY_X
  @skip_left:

  lda INPUT_1
  and #%00000100
  cmp #%00000100
  bne @skip_down
  lda ENTITY_X
  ldx #$03
  @down_shift_rol:		;preparar celda en x
  lsr A
  dex
  cpx #$00
  bne @down_shift_rol
  tax				;guardar celda offset en x
  lda SCREEN, x
  cmp #$01
  beq @skip_down		;ignorar si es un 0
  dec SCREEN, x			;cambiar la celda
  inc CURSOR_PRESSED		;indicar tecla presionada
  @skip_down:

  lda INPUT_1
  and #%00001000
  cmp #%00001000
  bne @skip_up
  lda ENTITY_X
  ldx #$03
  @up_shift_rol:		;preparar celda en x
  lsr A
  dex
  cpx #$00
  bne @up_shift_rol
  tax				;guardar celda offset en x
  lda SCREEN, x
  cmp #$10
  beq @skip_up			;ignorar si es un f
  inc SCREEN, x			;cambiar la celda
  inc CURSOR_PRESSED		;indicar tecla presionada
  @skip_up:


  lda INPUT_1
  and #%00010000
  cmp #%00010000
  bne @skip_start
			;podria hacerlo con un loop pero solo son 2 digitos
  lda #$01
  sta SCREEN + $12		;peparar el digito carry
  clc
  lda SCREEN + $01		;primer digito
  adc SCREEN + $04
  tax
  dex
  dex
  txa
  and #$0f
  sta SCREEN + $14
  inc SCREEN + $14		;ajuste grafico
  txa
  rol A
  rol A
  rol A
  rol A
  lda SCREEN + $00		;segundo digito
  adc SCREEN + $03
  tax
  dex
  dex
  txa
  and #$0f
  sta SCREEN + $13
  inc SCREEN + $13		;ajuste grafico
  txa
  rol A
  rol A
  rol A
  rol A
  lda #$00
  sta SCREEN + $11		;digito sin usar
  adc SCREEN + $12		;digito carry
  sta SCREEN + $12

  inc CURSOR_PRESSED		;indicar tecla presionada
  @skip_start:


  @skip_move_2:
  lda INPUT_1
  cmp #%00000000
  bne @skip_not_pressed		;si no hay input se resetea el bloqueo
  sta CURSOR_PRESSED

  @skip_not_pressed:

cursor_blink:
  lda CURSOR_CLOCK
  ldx #$05	;load n
  @rol_loop:	;divide by 2 n times
  lsr A
  dex
  cpx #$00
  bne @rol_loop
  and #%00000001
  clc
  adc #$10	;sprite palette offset
  sta CURSOR_BLINK

  rti


palettes:
  ; Background Palette
  .byte $0f, $02, $12, $22
  .byte $0f, $03, $13, $23
  .byte $0f, $04, $14, $24
  .byte $0f, $05, $15, $25

  ; Sprite Palette
  .byte $0f, $12, $22, $32
  .byte $0f, $13, $23, $33
  .byte $0f, $14, $24, $34
  .byte $0f, $15, $25, $35


sprites_id:
  .byte $15

sprites_config:
  .byte %00000000

; Character memory
.segment "CHARS"

  .byte %00000000	; blank 00
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 0 01
  .byte %00011000
  .byte %00100100
  .byte %00100100
  .byte %00100100
  .byte %00100100
  .byte %00011000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 1 02
  .byte %00001000
  .byte %00011000
  .byte %00001000
  .byte %00001000
  .byte %00001000
  .byte %00111100
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 2 03
  .byte %00011000
  .byte %00100100
  .byte %00100100
  .byte %00001000
  .byte %00010000
  .byte %00111100
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 3 04
  .byte %00011000
  .byte %00100100
  .byte %00001000
  .byte %00000100
  .byte %00100100
  .byte %00011000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 4 05
  .byte %00100100
  .byte %00100100
  .byte %00100100
  .byte %00011100
  .byte %00000100
  .byte %00000100
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 5 06
  .byte %00111100
  .byte %00100000
  .byte %00111000
  .byte %00000100
  .byte %00100100
  .byte %00011000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 6 07
  .byte %00011000
  .byte %00100000
  .byte %00111000
  .byte %00100100
  .byte %00100100
  .byte %00011000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 7 08
  .byte %00111100
  .byte %00000100
  .byte %00001000
  .byte %00001000
  .byte %00010000
  .byte %00010000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 8 09
  .byte %00011000
  .byte %00100100
  .byte %00011000
  .byte %00100100
  .byte %00100100
  .byte %00011000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; 9 0a
  .byte %00011000
  .byte %00100100
  .byte %00100100
  .byte %00011100
  .byte %00000100
  .byte %00000100
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; a 0b
  .byte %00000000
  .byte %00000000
  .byte %00011100
  .byte %00100100
  .byte %00100100
  .byte %00011100
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; b 0c
  .byte %00100000
  .byte %00100000
  .byte %00111000
  .byte %00100100
  .byte %00100100
  .byte %00111000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; c 0d
  .byte %00000000
  .byte %00011000
  .byte %00100100
  .byte %00100000
  .byte %00100100
  .byte %00011000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; d 0e
  .byte %00000100
  .byte %00000100
  .byte %00011100
  .byte %00100100
  .byte %00100100
  .byte %00011100
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; e 0f
  .byte %00000000
  .byte %00011000
  .byte %00100100
  .byte %00111100
  .byte %00100000
  .byte %00011100
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; f 10
  .byte %00011100
  .byte %00100000
  .byte %00111000
  .byte %00100000
  .byte %00100000
  .byte %00100000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; + 011
  .byte %00011000
  .byte %00011000
  .byte %01111110
  .byte %01111110
  .byte %00011000
  .byte %00011000
  .byte %00000000
  .byte %00000000	;
  .byte %00001000
  .byte %00001000
  .byte %00000000
  .byte %00000110
  .byte %00001000
  .byte %00001000
  .byte %00000000

  .byte %00000000	; - 12
  .byte %00000000
  .byte %00000000
  .byte %01111110
  .byte %01111110
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00111110
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; x 13
  .byte %01100110
  .byte %01111110
  .byte %00111100
  .byte %00111100
  .byte %01111110
  .byte %01100110
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00100100
  .byte %00010000
  .byte %00001000
  .byte %00100100
  .byte %00000000
  .byte %00000000

  .byte %00000000	; % 14
  .byte %01100110
  .byte %01101110
  .byte %00011100
  .byte %00111000
  .byte %01110110
  .byte %01100110
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00100100
  .byte %00001000
  .byte %00010000
  .byte %00100000
  .byte %00000010
  .byte %00000000

  .byte %00000000	; cursor 15
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %11111111
  .byte %11111111
  .byte %00000000	;
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00000000

  .byte %00000000	; = 16
  .byte %01111110
  .byte %01111110
  .byte %00000000
  .byte %00000000
  .byte %01111110
  .byte %01111110
  .byte %00000000
  .byte %00000000	;
  .byte %00000000
  .byte %00111110
  .byte %00000000
  .byte %00000000
  .byte %00000000
  .byte %00111110
  .byte %00000000
