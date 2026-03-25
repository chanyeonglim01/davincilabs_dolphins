/**
 * @file main.c
 * @brief Dolphin helium drone firmware entry point
 *
 * MCU: STM32G431KB
 * - System clock: 170 MHz (HSI + PLL)
 * - 100Hz control loop via TIM6 interrupt
 */
#include "stm32g4xx_hal.h"
#include "app/control_task.h"
#include "middleware/param.h"

/* ---- Forward declarations ---------------------------------------------- */

static void SystemClock_Config(void);
static void TIM6_Init(void);

/* ---- TIM6 handle for 100Hz tick ---------------------------------------- */

static TIM_HandleTypeDef htim6;
static volatile bool control_tick = false;

/* ---- TIM6 ISR: 100Hz flag ---------------------------------------------- */

void TIM6_DAC_IRQHandler(void)
{
    HAL_TIM_IRQHandler(&htim6);
}

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
    if (htim->Instance == TIM6) {
        control_tick = true;
    }
}

/* ---- Main -------------------------------------------------------------- */

int main(void)
{
    /* HAL init */
    HAL_Init();

    /* Configure system clock to 170 MHz */
    SystemClock_Config();

    /* Initialize 100Hz timer (TIM6) */
    TIM6_Init();

    /* Initialize all control subsystems */
    control_task_init();

    /* Start 100Hz timer */
    HAL_TIM_Base_Start_IT(&htim6);

    /* Main loop */
    while (1) {
        if (control_tick) {
            control_tick = false;
            control_task_run();
        }

        /* Low-priority background tasks can go here:
         * - Telemetry TX (future)
         * - LED status blink (future)
         * - WDT kick (future)
         */
        __WFI(); /* Sleep until next interrupt */
    }
}

/* ---- System Clock Configuration ----------------------------------------
 * HSI16 -> PLL -> 170 MHz SYSCLK
 * APB1/APB2 = 170 MHz (no division)
 * ------------------------------------------------------------------------ */
static void SystemClock_Config(void)
{
    /* Voltage scaling MUST be set BEFORE configuring PLL to 170 MHz.
     * SCALE1_BOOST is required for >150 MHz operation on STM32G4. */
    __HAL_RCC_PWR_CLK_ENABLE();
    HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1_BOOST);

    RCC_OscInitTypeDef osc = {0};
    osc.OscillatorType = RCC_OSCILLATORTYPE_HSI;
    osc.HSIState       = RCC_HSI_ON;
    osc.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
    osc.PLL.PLLState   = RCC_PLL_ON;
    osc.PLL.PLLSource  = RCC_PLLSOURCE_HSI;
    osc.PLL.PLLM       = RCC_PLLM_DIV4;   /* 16/4 = 4 MHz */
    osc.PLL.PLLN       = 85;               /* 4*85 = 340 MHz VCO */
    osc.PLL.PLLP       = RCC_PLLP_DIV2;    /* not used */
    osc.PLL.PLLQ       = RCC_PLLQ_DIV2;    /* 170 MHz */
    osc.PLL.PLLR       = RCC_PLLR_DIV2;    /* 170 MHz SYSCLK */
    HAL_RCC_OscConfig(&osc);

    RCC_ClkInitTypeDef clk = {0};
    clk.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                        | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clk.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
    clk.AHBCLKDivider  = RCC_SYSCLK_DIV1;
    clk.APB1CLKDivider = RCC_HCLK_DIV1;
    clk.APB2CLKDivider = RCC_HCLK_DIV1;
    HAL_RCC_ClockConfig(&clk, FLASH_LATENCY_4);
}

/* ---- TIM6: 100Hz periodic interrupt ------------------------------------
 * Timer clock = 170 MHz
 * Prescaler = 17000-1 -> 10 kHz counter clock
 * Period = 100-1 -> 100 Hz interrupt
 * ------------------------------------------------------------------------ */
static void TIM6_Init(void)
{
    __HAL_RCC_TIM6_CLK_ENABLE();

    htim6.Instance           = TIM6;
    htim6.Init.Prescaler     = 17000 - 1;
    htim6.Init.CounterMode   = TIM_COUNTERMODE_UP;
    htim6.Init.Period        = 100 - 1;
    htim6.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
    HAL_TIM_Base_Init(&htim6);

    /* Enable TIM6 interrupt */
    HAL_NVIC_SetPriority(TIM6_DAC_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(TIM6_DAC_IRQn);
}
