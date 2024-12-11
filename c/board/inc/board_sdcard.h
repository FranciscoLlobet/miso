#include <stdint.h>

/* SD CARD Functionality */
void BOARD_SD_Card_Init(void);
void BOARD_SD_Card_Enable(void);
void BOARD_SD_Card_Disable(void);

void BOARD_SD_CARD_Select(void);
void BOARD_SD_CARD_Deselect(void);
void BOARD_SD_CARD_SetFastBaudrate(void);
void BOARD_SD_CARD_SetSlowBaudrate(void);
uint32_t BOARD_SD_CARD_Send(const void *buffer, int count);
uint32_t BOARD_SD_CARD_Recieve(void *buffer, int count);
uint32_t BOARD_SD_CARD_IsInserted(void);