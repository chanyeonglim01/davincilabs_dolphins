/**
 * @file sbus_rx.h
 * @brief FrSky XM+ SBUS receiver driver (USART1, RXINV, DMA)
 *
 * SBUS protocol: 100000 baud, 8E2, inverted
 * 25-byte frame: [0x0F] [ch1..ch16 packed 11-bit] [flags] [0x00]
 */
#ifndef SBUS_RX_H
#define SBUS_RX_H

#include <stdint.h>
#include <stdbool.h>

#define SBUS_NUM_CHANNELS   16
#define SBUS_FRAME_SIZE     25
#define SBUS_HEADER         0x0F
#define SBUS_FOOTER         0x00

/* Raw SBUS range: 172..1811, center 992 */
#define SBUS_RAW_MIN        172
#define SBUS_RAW_MAX        1811
#define SBUS_RAW_CENTER     992

/* Flags byte bits */
#define SBUS_FLAG_CH17      (1 << 0)
#define SBUS_FLAG_CH18      (1 << 1)
#define SBUS_FLAG_FRAMELOST (1 << 2)
#define SBUS_FLAG_FAILSAFE  (1 << 3)

typedef struct {
    uint16_t channels[SBUS_NUM_CHANNELS]; /* raw 11-bit values */
    bool     frame_lost;
    bool     failsafe;
    uint32_t last_valid_tick;             /* HAL_GetTick() of last good frame */
    bool     new_frame;                   /* set by ISR, cleared by consumer */
} sbus_data_t;

/**
 * @brief Initialize SBUS receiver on USART1 with DMA
 * Configures USART1: 100000 baud, 8E2, RXINV, DMA circular
 */
void sbus_rx_init(void);

/**
 * @brief Process received SBUS data (call from main loop)
 * Parses DMA buffer if a complete frame is available
 */
void sbus_rx_process(void);

/**
 * @brief Get pointer to current SBUS data
 * @return Pointer to sbus_data_t (read-only recommended)
 */
const sbus_data_t* sbus_rx_get_data(void);

/**
 * @brief Check if SBUS signal is valid (no timeout, no failsafe)
 * @param timeout_ms Maximum age of last valid frame in ms
 * @return true if valid
 */
bool sbus_rx_is_valid(uint32_t timeout_ms);

#endif /* SBUS_RX_H */
