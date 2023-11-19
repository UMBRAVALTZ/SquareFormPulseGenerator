.386
;Задайте объём ПЗУ в байтах
RomSize    EQU   4096

			MatrixPowerPortL = 0FBh; Матрицы 0-7
			MatrixPowerPortH = 0F7h; Матрицы 8-15
			MatrixColumnPort = 0FEh; 
			MatrixRowPort = 0FDh; 
			DisplayPowerPort = 0EFh ;0-2 Частота, 3 Амплитуда, 4 Длительность импульса
			DisplaySegmentsPort = 0DFh
			KeyboardPort = 0FEh
			MS = 1000
			NMax = 50

IntTable   SEGMENT use16 AT 0
;Здесь размещаются адреса обработчиков прерываний
IntTable   ENDS

Data       SEGMENT use16 AT 40h
;Здесь размещаются описания переменных

			FrequancyBCD db 2 dup(?) ;Частота в десятичном коде
			FrequancyImage db 3 dup(?) ;Частота в десятичном коде в распакованном формате
			Frequancy db ? ;Частота
			Amplitude db ? ;Амплитуда
			PulseDuration db ? ;Длительность импульса
			PauseDuration db ? ;Длительность паузы
			PulsePeriod db ? ;Период
			NoInputErrorFlag db ? ;Фгал неактивных кнопок
			PolarityFlag db ? ;Флаг полярности
			DataHexArr db 10 dup(?)
			DataHexTabl db 10 dup(?)
			KeyImage db ? ; FF: ничего, FE: + Freq, FD: - Freq, FB: + Ampl, F7: - Ampl, EF: + PulDur, DF: - PulDur, BF: Generation, 7F: Polarity
			OldButton db ? ; Предыдущее состояние кнопки
			PulsesImage db 128 dup(?) ;Массив отображения импульсов
			PulsesCount db ? ;Количесвто импульсов
			StartPosition db ? ;Начальная позиция указателя

Data       ENDS

;Задайте необходимый адрес стека
Stk			SEGMENT use16  AT 00FFh
;Задайте необходимый размер стека
           dw    16 dup (?)
StackTop     Label Word
Stk        ENDS

InitData   SEGMENT use16
InitDataStart:
;Здесь размещаются описания констант
InitDataEnd:
InitData   ENDS

Code       SEGMENT use16
;Здесь размещаются описания констант

			ASSUME cs:Code,ds:Data,es:Data, ss:Stk
			HexArr DB 00h,01h,02h,03h,04h,05h,06h,07h,08h,09h
			HexTabl DB 0C0h,0F3h,89h,0A1h,0B2h,0A4h,84h,0F1h,80h,0A0h
			
Initialization PROC ;Функциональная подготовка
			CALL CopyArraysToDataSegment
			XOR AX, AX
			MOV Frequancy, 20
			MOV Amplitude, 5; 
			MOV PulseDuration, 5
			MOV KeyImage, 0FFh
			MOV NoInputErrorFlag, 0FFh
			MOV PolarityFlag, AH
			MOV FrequancyImage+0, AH
			MOV FrequancyImage+1, AH
			MOV FrequancyImage+2, AH
			MOV FrequancyBCD+0, AH
			MOV FrequancyBCD+1, AH
			MOV FrequancyBCD+2, AH
			MOV PulsePeriod, AH
			MOV PulsesCount, AH
			MOV PauseDuration, AH
			MOV OldButton, AH
			LEA DI, PulsesImage
			MOV CX, 128
M1:			MOV [DI], AL
			INC DI
			LOOP M1
			
			RET
Initialization ENDP

CopyArraysToDataSegment PROC 
			MOV CX, 10 ;Загрузка счётчика циклов
			LEA BX, HexArr ;Загрузка адреса массива цифр
			LEA BP, HexTabl ;Загрузка адреса таблицы преобразования
			LEA DI, DataHexArr ;Загрузка адреса массива цифр в сегменте данных
			LEA SI, DataHexTabl ;Загрузка адреса таблицы преобразования в сегменте данных
M0:
			MOV AL, CS:[BX] ;Чтение цифры из массива в аккумулятор
			MOV [DI], AL ;Запись цифры в сегмент данных/DataHexArr
			INC BX ;Модификация адреса HexArr
			INC DI ;Модификация адреса DataHexArr
			LOOP M0
			
			MOV CX, 10 ;Загрузка счётчика циклов
M1:
			MOV AH, CS:[BP] ;Чтение графического образа из таблицы преобразования
			MOV [SI], AH ;Запись графического образа в сегмент данных/DataHexTabl
			INC BP ;Модификация адреса HexTabl
			INC SI ;Модификация адреса DataHexTabl
			LOOP M1
			XOR BP,BP
			RET
CopyArraysToDataSegment ENDP

KeyRead    PROC   ;Чтение кнопок
			MOV DX, KeyboardPort
            IN AL, KeyboardPort
			CALL VibrDestr
            MOV AH, AL
            XOR AL, OldButton
            AND AL, AH
			NOT AL
			MOV OldButton, AH
			MOV KeyImage, AL		
			RET
KeyRead    ENDP

VibrDestr  PROC  
VD1:        mov   ah,al       ;Сохранение исходного состояния
            mov   bh,0        ;Сброс счётчика повторений
VD2:        in    al,dx       ;Ввод текущего состояния
            cmp   ah,al       ;Текущее состояние=исходному?
            jne   VD1         ;Переход, если нет
            inc   bh          ;Инкремент счётчика повторений
            cmp   bh,NMax     ;Конец дребезга?
            jne   VD2         ;Переход, если нет
            mov   al,ah       ;Восстановление местоположения данных
            ret
VibrDestr  ENDP

KeyCheck PROC 
			CMP KeyImage, 0FFh
			JNZ M1
			MOV NoInputErrorFlag, 0FFh
			JMP M2
M1:			MOV NoInputErrorFlag, 00h
M2:			RET
KeyCheck ENDP

DataSetting PROC 
			CMP NoInputErrorFlag, 0FFh
			JZ M1
			CALL FrequancyAddition
			CALL FrequancySubtraction
			CALL AmplitudeAddition
			CALL AmplitudeSubtraction
			CALL PulseDurationAddition
			CALL PulseDurationSubtraction
			CALL PolaritySetting
			CALL PulsePeriodAndPauseCalculation
			CALL PulsesCountCalculation
			CALL StartPositionSetting
M1:			
			RET
DataSetting ENDP

FrequancyAddition PROC 
			CMP KeyImage, 0FEh
			JNZ M1
			CMP Frequancy, 150
			JZ M1
			ADD Frequancy, 10			
M1:			RET
FrequancyAddition ENDP

FrequancySubtraction PROC 
			CMP KeyImage, 0FDh
			JNZ M1
			CMP Frequancy, 20
			JZ M1
			SUB Frequancy, 10			
M1:			RET
FrequancySubtraction ENDP

AmplitudeAddition PROC 
			CMP KeyImage, 0FBh
			JNZ M1
			CMP Amplitude, 5
			JZ M1		
			INC Amplitude			
M1:			RET
AmplitudeAddition ENDP

AmplitudeSubtraction PROC 
			CMP KeyImage, 0F7h
			JNZ M1
			CMP Amplitude, 0
			JZ M1			
			DEC Amplitude		
M1:			RET
AmplitudeSubtraction ENDP

PulseDurationAddition PROC 
			CMP KeyImage, 0EFh
			JNZ M1
			CMP PulseDuration, 5
			JZ M1
			INC PulseDuration			
M1:			RET
PulseDurationAddition ENDP

PulseDurationSubtraction PROC 
			CMP KeyImage, 0DFh
			JNZ M1
			CMP PulseDuration, 1
			JZ M1
			DEC PulseDuration			
M1:			RET
PulseDurationSubtraction ENDP

PolaritySetting PROC 
			CMP KeyImage, 0BFh
			JNZ M1
			NOT PolarityFlag
M1:			RET
PolaritySetting ENDP

PulsePeriodAndPauseCalculation PROC  
			MOV AX, MS
			DIV Frequancy
			MOV PulsePeriod, AL
			SUB AL, PulseDuration
			MOV PauseDuration, AL
			RET
PulsePeriodAndPauseCalculation ENDP

PulsesCountCalculation PROC 
			XOR AX, AX
			MOV AL, LENGTH PulsesImage
			DIV PulsePeriod
			MOV PulsesCount, AL
			RET
PulsesCountCalculation ENDP

StartPositionSetting PROC 
			CMP PolarityFlag, 00h
			JNZ M1
			MOV StartPosition, 20h
			JMP M2
M1:			MOV StartPosition, 04h
M2:			
			RET
StartPositionSetting ENDP

BinaryToBCD PROC 
			XOR BX, BX
			MOV FrequancyBCD+0, BL
			MOV FrequancyBCD+1, BL
			MOV FrequancyBCD+2, BL
			MOV BL, Frequancy
			MOV CX, 8
M2:			LEA DI, FrequancyBCD
			SHL BL, 1
			PUSH CX
			MOV CX, 2
M1:			MOV AL, [DI]
			ADC AL, [DI]
			DAA
			MOV [DI], AL
			INC DI
			LOOP M1
			POP CX
			LOOP M2
			RET
BinaryToBCD ENDP

UnpackFrequancyBCD PROC 
			MOV AL, FrequancyBCD+0
			MOV BL, AL
			AND AL, 0Fh
			MOV FrequancyImage+0, AL
			SHR BL,4
			MOV FrequancyImage+1, BL
			MOV AL, FrequancyBCD+1
			AND AL, 0Fh
			MOV FrequancyImage+2, AL
			RET
UnpackFrequancyBCD ENDP

PulseImageForming PROC 
			LEA BX, PulsesImage
			XOR DI, DI
			
			CALL XAxisForming
			
			CMP Amplitude, 00h
			JZ M2
			XOR DI, DI
			
			MOV CL, PulsesCount
			INC CL
			
M1:			PUSH CX

			CALL AmplitudeUpImageForming
			CALL PulseDurationImageForming
			CALL AmplitudeDownImageForming
			CALL PauseDurationImageForming
			
			POP CX
			LOOP M1
M2:			RET
PulseImageForming ENDP

XAxisForming PROC 

			MOV CL, 128
			MOV AH, StartPosition
			MOV AL, AH
			
			CMP PolarityFlag, 0FFh
			JNZ M1
			SHR AH, 2
M3:			CMP Amplitude, 00h
			JNZ M2
			OR AH, AL
			JMP M2
			
M1:			SHL AH, 2
			JMP M3
			;CMP Amplitude, 00h
			;JNZ M2
			OR AH, AL

M2:			OR [BX+DI], AH
			AND [BX+DI], AH
			INC DI
			LOOP M2

			RET
XAxisForming ENDP

AmplitudeUpImageForming PROC 
			MOV CL, Amplitude
			MOV AH, StartPosition
M1:			CMP DI, 128
			JZ M7
			OR [BX+DI], AH
			CMP PolarityFlag, 00h
			JNZ M2
			SHR AH, 1
			JMP M3
M2:			SHL AH, 1
			
M3:			LOOP M1
M7:			RET
AmplitudeUpImageForming ENDP

PulseDurationImageForming PROC 
			CMP PulseDuration, 1
			JZ M7
			MOV CL, PulseDuration; Длительность импульса - 1
			DEC CL
M2:			CMP DI, 128
			JZ M7
			OR [BX+DI], AH
			INC DI
			LOOP M2
M7:			RET
PulseDurationImageForming ENDP

AmplitudeDownImageForming PROC 
			MOV CL, Amplitude
M1:			CMP DI, 128
			JZ M7
			OR [BX+DI], AH
			CMP PolarityFlag, 00h
			JNZ M2
			SHL AH, 1
			JMP M3
M2:			SHR AH, 1
M3:			LOOP M1
M7:			RET
AmplitudeDownImageForming ENDP

PauseDurationImageForming PROC 
			MOV CL, PauseDuration
			INC CL
M4:			CMP DI, 128
			JZ M7
			OR [BX+DI], AH
			INC DI
			LOOP M4
M7:			RET
PauseDurationImageForming ENDP

DisplayData PROC 
			CALL DisplayFrequancy
			CALL DisplayAmplitude
			CALL DisplayPulseDuration
			RET
DisplayData ENDP
		   
DisplayFrequancy     PROC  ;Вывод частоты на дисплей
			LEA BX, DataHexTabl 
            MOV AH, FrequancyImage+0
            MOV AL, AH               ;теперь в al старшая цифра
            XLAT			   ;табличное преобразование старшей цифры
            OUT DisplaySegmentsPort, AL    ;выводим на страший индикатор
            MOV AL, 1            
            OUT DisplayPowerPort, AL    ;зажигаем старший индикатор    
            MOV AL,00h             
            OUT DisplayPowerPort, AL    ;гасим индикатор
		    MOV AH, FrequancyImage+1      ;загружаем в регистры
            MOV AL, AH              ;текущее значение суммы                 
            XLAT 			;табличное преобразование младшей цифры
            OUT DisplaySegmentsPort, AL    ;Выводим на младший индикатор            
            MOV AL, 2            
            OUT DisplayPowerPort, AL    ;зажигаем младший индикатор
            MOV AL,00h
            OUT DisplayPowerPort, AL    ;гасим индикатор
			MOV AH, FrequancyImage+2      ;загружаем в регистры
            MOV AL, AH              ;текущее значение суммы                 
            XLAT			;табличное преобразование младшей цифры
            OUT DisplaySegmentsPort, AL    ;Выводим на младший индикатор            
            MOV AL, 4            
            OUT DisplayPowerPort, AL    ;зажигаем младший индикатор
            MOV AL,00h
            OUT DisplayPowerPort, AL    ;гасим индикатор
            RET
DisplayFrequancy     ENDP

DisplayAmplitude     PROC  ;Вывод амплитуды на дисплей
			LEA BX, DataHexTabl 
            MOV AL, Amplitude
            XLAT 							;табличное преобразование старшей цифры
            OUT DisplaySegmentsPort, AL    ;выводим на страший индикатор
            MOV AL, 8            
            OUT DisplayPowerPort, AL    ;зажигаем старший индикатор    
            MOV AL,00h             
            OUT DisplayPowerPort, AL    ;гасим индикатор
            RET
DisplayAmplitude     ENDP

DisplayPulseDuration     PROC  ;Вывод длительности импульса на дисплей
			LEA BX, DataHexTabl 
            MOV AL, PulseDuration
            XLAT		   ;табличное преобразование старшей цифры
            OUT DisplaySegmentsPort, AL    ;выводим на страший индикатор
            MOV AL, 16            
            OUT DisplayPowerPort, AL    ;зажигаем старший индикатор    
            MOV AL,00h             
            OUT DisplayPowerPort, AL    ;гасим индикатор
            RET
DisplayPulseDuration     ENDP

MatrixOutput PROC 
			LEA SI, PulsesImage
			MOV DL, MatrixPowerPortL
			MOV BL, 1
			MOV AH, 1
			MOV CX, 2
M3:			PUSH CX
			
			MOV CX, 8
			
M2:			PUSH CX
			
			MOV CX, 8
			
M1:			MOV AL, [SI]
			OUT MatrixRowPort, AL
			MOV AL, AH
			OUT MatrixColumnPort, AL
			MOV AL, BL
			OUT DX, AL
			MOV AL, 0
			OUT MatrixRowPort, AL
			OUT MatrixColumnPort, AL
			OUT DX, AL 
			ROL AH, 1
			INC SI
			LOOP M1
			ROL BL, 1
			POP CX
			LOOP M2
			
			POP CX
			ROL DL, 1
			LOOP M3
			RET
MatrixOutput ENDP

Start:
            mov   ax,Data
            mov   ds,ax
            mov   es,ax
            mov   ax,Stk
            mov   ss,ax
            lea   sp,StackTop
			
;Здесь размещается код программы
			CALL Initialization
ILOOP:
			CALL KeyRead
			CALL KeyCheck
			CALL DataSetting
			CALL BinaryToBCD
			CALL UnpackFrequancyBCD	
			CALL PulseImageForming			
			CALL DisplayData
			CALL MatrixOutput
			JMP ILOOP

;В следующей строке необходимо указать смещение стартовой точки
           org   RomSize-16-((InitDataEnd-InitDataStart+15) AND 0FFF0h)
           ASSUME cs:NOTHING
           jmp   Far Ptr Start
Code       ENDS
END		Start
