/**
 * @file sbus_rx.c
 * @brief FrSky XM+ SBUS receiver driver implementation
 *
 * Uses USART1 with DMA in circular mode.
 * STM32G431KB USART1 supports hardware RX inversion (RXINV).
 */
#include "sbus_rx.h"
#include "stm32g4xx_hal.h"
#include <string.h>

/* ---- Private ----------------------------------------------------------- */

static UART_HandleTypeDef huart_sbus;
static DMA_HandleTypeDef  hdma_sbus_rx;

/* Double-buffer: DMA writes into dma_buf, we parse from parse_buf */
static uint8_t dma_buf[SBUS_FRAME_SIZE * 2];
static uint8_t parse_buf[SBUS_FRAME_SIZE];

static sbus_data_t sbus_data;
static volatile bool frame_ready = false;

/* ---- DMA / USART callbacks --------------------------------------------- */

/**
 * Called by HAL when DMA transfer completes (full buffer) or half-complete.
 * We scan the DMA buffer for a valid SBUS frame.
 */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART1) {
        frame_ready = true;
    }
}

void HAL_UART_RxHalfCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART1) {
        frame_ready = true;
    }
}

/* ---- Frame scanning ---------------------------------------------------- */

/**
 * Scan the DMA circular buffer for a valid SBUS frame
 * Returns true if a frame starting with 0x0F and ending with 0x00 is found
 */
static bool sbus_find_frame(const uint8_t *buf, uint16_t len, uint8_t *out)
{
    for (uint16_t i = 0; i + SBUS_FRAME_SIZE <= len; i++) {
        if (buf[i] == SBUS_HEADER &&
            buf[i + SBUS_FRAME_SIZE - 1] == SBUS_FOOTER) {
            memcpy(out, &buf[i], SBUS_FRAME_SIZE);
            return true;
        }
    }
    return false;
}

/**
 * Parse 25-byte SBUS frame into channel values.
 * Channels are packed as 11-bit values in little-endian bit order.
 */
static void sbus_parse_frame(const uint8_t *frame, sbus_data_t *data)
{
    const uint8_t *p = &frame[1]; /* skip header byte */

    data->channels[0]  = (uint16_t)((p[0]       | p[1]  << 8)                   & 0x07FF);
    data->channels[1]  = (uint16_t)((p[1]  >> 3  | p[2]  << 5)                   & 0x07FF);
    data->channels[2]  = (uint16_t)((p[2]  >> 6  | p[3]  << 2  | p[4]  << 10)   & 0x07FF);
    data->channels[3]  = (uint16_t)((p[4]  >> 1  | p[5]  << 7)                   & 0x07FF);
    data->channels[4]  = (uint16_t)((p[5]  >> 4  | p[6]  << 4)                   & 0x07FF);
    data->channels[5]  = (uint16_t)((p[6]  >> 7  | p[7]  << 1  | p[8]  << 9)    & 0x07FF);
    data->channels[6]  = (uint16_t)((p[8]  >> 2  | p[9]  << 6)                   & 0x07FF);
    data->channels[7]  = (uint16_t)((p[9]  >> 5  | p[10] << 3)                   & 0x07FF);
    data->channels[8]  = (uint16_t)((p[11]       | p[12] << 8)                   & 0x07FF);
    data->channels[9]  = (uint16_t)((p[12] >> 3  | p[13] << 5)                   & 0x07FF);
    data->channels[10] = (uint16_t)((p[13] >> 6  | p[14] << 2  | p[15] << 10)   & 0x07FF);
    data->channels[11] = (uint16_t)((p[15] >> 1  | p[16] << 7)                   & 0x07FF);
    data->channels[12] = (uint16_t)((p[16] >> 4  | p[17] << 4)                   & 0x07FF);
    data->channels[13] = (uint16_t)((p[17] >> 7  | p[18] << 1  | p[19] << 9)    & 0x07FF);
    data->channels[14] = (uint16_t)((p[19] >> 2  | p[20] << 6)                   & 0x07FF);
    data->channels[15] = (uint16_t)((p[20] >> 5  | p[21] << 3)                   & 0x07FF);

    uint8_t flags = frame[23];
    data->frame_lost = (flags & SBUS_FLAG_FRAMELOST) != 0;
    data->failsafe   = (flags & SBUS_FLAG_FAILSAFE)  != 0;
}

/* ---- Public API -------------------------------------------------------- */

void sbus_rx_init(void)
{
    memset(&sbus_data, 0, sizeof(sbus_data));

    /* ---- GPIO: USART1_RX = PA10 (AF7) ---- */
    __HAL_RCC_GPIOA_CLK_ENABLE();
    GPIO_InitTypeDef gpio = {0};
    gpio.Pin       = GPIO_PIN_10;
    gpio.Mode      = GPIO_MODE_AF_PP;
    gpio.Pull      = GPIO_PULLUP;
    gpio.Speed     = GPIO_SPEED_FREQ_LOW;
    gpio.Alternate = GPIO_AF7_USART1;
    HAL_GPIO_Init(GPIOA, &gpio);

    /* ---- USART1: 100000 baud, 8E2, RX inversion ---- */
    __HAL_RCC_USART1_CLK_ENABLE();
    huart_sbus.Instance          = USART1;
    huart_sbus.Init.BaudRate     = 100000;
    huart_sbus.Init.WordLength   = UART_WORDLENGTH_9B; /* 8 data + parity = 9 */
    huart_sbus.Init.StopBits     = UART_STOPBITS_2;
    huart_sbus.Init.Parity       = UART_PARITY_EVEN;
    huart_sbus.Init.Mode         = UART_MODE_RX;
    huart_sbus.Init.HwFlowCtl   = UART_HWCONTROL_NONE;
    huart_sbus.Init.OverSampling = UART_OVERSAMPLING_16;
    huart_sbus.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_RXINVERT_INIT;
    huart_sbus.AdvancedInit.RxPinLevelInvert = UART_ADVFEATURE_RXINV_ENABLE;
    HAL_UART_Init(&huart_sbus);

    /* ---- DMA1 Channel 1 for USART1_RX ---- */
    __HAL_RCC_DMA1_CLK_ENABLE();
    __HAL_RCC_DMAMUX1_CLK_ENABLE();

    hdma_sbus_rx.Instance                 = DMA1_Channel1;
    hdma_sbus_rx.Init.Request             = DMA_REQUEST_USART1_RX;
    hdma_sbus_rx.Init.Direction           = DMA_PERIPH_TO_MEMORY;
    hdma_sbus_rx.Init.PeriphInc           = DMA_PINC_DISABLE;
    hdma_sbus_rx.Init.MemInc              = DMA_MINC_ENABLE;
    hdma_sbus_rx.Init.PeriphDataAlignment = DMA_PDATAALIGN_BYTE;
    hdma_sbus_rx.Init.MemDataAlignment    = DMA_MDATAALIGN_BYTE;
    hdma_sbus_rx.Init.Mode                = DMA_CIRCULAR;
    hdma_sbus_rx.Init.Priority            = DMA_PRIORITY_HIGH;
    HAL_DMA_Init(&hdma_sbus_rx);

    __HAL_LINKDMA(&huart_sbus, hdmarx, hdma_sbus_rx);

    /* NVIC */
    HAL_NVIC_SetPriority(DMA1_Channel1_IRQn, 1, 0);
    HAL_NVIC_EnableIRQ(DMA1_Channel1_IRQn);
    HAL_NVIC_SetPriority(USART1_IRQn, 1, 1);
    HAL_NVIC_EnableIRQ(USART1_IRQn);

    /* Start DMA circular reception */
    HAL_UART_Receive_DMA(&huart_sbus, dma_buf, sizeof(dma_buf));
}

void sbus_rx_process(void)
{
    if (!frame_ready) return;
    frame_ready = false;

    if (sbus_find_frame(dma_buf, sizeof(dma_buf), parse_buf)) {
        sbus_parse_frame(parse_buf, &sbus_data);
        if (!sbus_data.failsafe && !sbus_data.frame_lost) {
            sbus_data.last_valid_tick = HAL_GetTick();
            sbus_data.new_frame = true;
        }
    }
}

const sbus_data_t* sbus_rx_get_data(void)
{
    return &sbus_data;
}

bool sbus_rx_is_valid(uint32_t timeout_ms)
{
    if (sbus_data.failsafe) return false;
    if (sbus_data.last_valid_tick == 0) return false;
    return (HAL_GetTick() - sbus_data.last_valid_tick) < timeout_ms;
}

/* ---- IRQ Handlers (weak override) -------------------------------------- */

void DMA1_Channel1_IRQHandler(void)
{
    HAL_DMA_IRQHandler(&hdma_sbus_rx);
}

void USART1_IRQHandler(void)
{
    HAL_UART_IRQHandler(&huart_sbus);
}
