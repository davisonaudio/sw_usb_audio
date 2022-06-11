#include <xs1.h>
#include <platform.h>
#include "xassert.h"
#include "xua.h"
#include "i2c.h"
#include "tlv320aic3204.h"

// CODEC I2C lines
on tile[0]: port p_i2c_scl = XS1_PORT_1N;
on tile[0]: port p_i2c_sda = XS1_PORT_1O;

// CODEC reset line
on tile[1]: out port p_codec_reset  = PORT_CODEC_RST_N;

// CODEC Reset
#define CODEC_RELEASE_RESET      (0x8) // Release codec from

// App PLL setup
#define APP_PLL_CTL_BYPASS       (0)   // 0 = no bypass, 1 = bypass.
#define APP_PLL_CTL_INPUT_SEL    (0)   // 0 = XTAL, 1 = sysPLL
#define APP_PLL_CTL_ENABLE       (1)   // 0 = disabled, 1 = enabled.

// 24MHz in, 24.576MHz out, integer mode
// Found exact solution:   IN  24000000.0, OUT  24576000.0, VCO 2457600000.0, RD  5, FD  512, OD 10, FOD  10
#define APP_PLL_CTL_OD_48        (4)   // Output divider = (OD+1)
#define APP_PLL_CTL_F_48         (511) // FB divider = (F+1)/2
#define APP_PLL_CTL_R_48         (4)   // Ref divider = (R+1)

#define APP_PLL_CTL_48           ((APP_PLL_CTL_BYPASS << 29) | (APP_PLL_CTL_INPUT_SEL << 28) | (APP_PLL_CTL_ENABLE << 27) |\
                                    (APP_PLL_CTL_OD_48 << 23) | (APP_PLL_CTL_F_48 << 8) | APP_PLL_CTL_R_48)

// Fractional divide is M/N
#define APP_PLL_FRAC_EN_48             (0)   // 0 = disabled
#define APP_PLL_FRAC_NPLUS1_CYCLES_48  (0)   // M value is this reg value + 1.
#define APP_PLL_FRAC_TOTAL_CYCLES_48   (0)   // N value is this reg value + 1.
#define APP_PLL_FRAC_48          ((APP_PLL_FRAC_EN_48 << 31) | (APP_PLL_FRAC_NPLUS1_CYCLES_48 << 8) | APP_PLL_FRAC_TOTAL_CYCLES_48)

// 24MHz in, 22.5792MHz out (44.1kHz * 512), frac mode
// Found exact solution:   IN  24000000.0, OUT  22579200.0, VCO 2257920000.0, RD  5, FD  470.400 (m =   2, n =   5), OD  5, FOD   10
#define APP_PLL_CTL_OD_441       (4)   // Output divider = (OD+1)
#define APP_PLL_CTL_F_441        (469) // FB divider = (F+1)/2
#define APP_PLL_CTL_R_441        (4)   // Ref divider = (R+1)

#define APP_PLL_CTL_441          ((APP_PLL_CTL_BYPASS << 29) | (APP_PLL_CTL_INPUT_SEL << 28) | (APP_PLL_CTL_ENABLE << 27) |\
                                    (APP_PLL_CTL_OD_441 << 23) | (APP_PLL_CTL_F_441 << 8) | APP_PLL_CTL_R_441)

#define APP_PLL_FRAC_EN_44             (1)   // 1 = enabled
#define APP_PLL_FRAC_NPLUS1_CYCLES_44  (1)   // M value is this reg value + 1.
#define APP_PLL_FRAC_TOTAL_CYCLES_44   (4)   // N value is this reg value + 1.define APP_PLL_CTL_R_441        (4)   // Ref divider = (R+1)
#define APP_PLL_FRAC_44   ((APP_PLL_FRAC_EN_44 << 31) | (APP_PLL_FRAC_NPLUS1_CYCLES_44 << 8) | APP_PLL_FRAC_TOTAL_CYCLES_44)

#define APP_PLL_DIV_INPUT_SEL    (1)   // 0 = sysPLL, 1 = app_PLL
#define APP_PLL_DIV_DISABLE      (0)   // 1 = disabled (pin connected to X1D11), 0 = enabled divider output to pin.
#define APP_PLL_DIV_VALUE        (4)   // Divide by N+1 - remember there's a /2 also afterwards for 50/50 duty cycle.
#define APP_PLL_DIV              ((APP_PLL_DIV_INPUT_SEL << 31) | (APP_PLL_DIV_DISABLE << 16) | APP_PLL_DIV_VALUE)

typedef enum
{
    AUDIOHW_CMD_REGWR,
    AUDIOHW_CMD_REGRD
} audioHwCmd_t;

static inline void AIC3204_REGREAD(unsigned reg, unsigned &val, client interface i2c_master_if i2c)
{
    i2c_regop_res_t result;
    val = i2c.read_reg(AIC3204_I2C_DEVICE_ADDR, reg, result);
}

static inline void AIC3204_REGWRITE(unsigned reg, unsigned val, client interface i2c_master_if i2c)
{
    i2c.write_reg(AIC3204_I2C_DEVICE_ADDR, reg, val);
}

void AudioHwRemote2(chanend c, client interface i2c_master_if i2c)
{
    while(1)
    {
        unsigned cmd;
        c :> cmd;

        if(cmd == AUDIOHW_CMD_REGRD)
        {
            unsigned regAddr, regVal;
            c :> regAddr;
            AIC3204_REGREAD(regAddr, regVal, i2c);
            c <: regVal;
        }
        else
        {
            unsigned regAddr, regValue;
            c :> regAddr;
            c :> regValue;
            AIC3204_REGWRITE(regAddr, regValue, i2c);
        }
    }
}

void AudioHwRemote(chanend c)
{
    i2c_master_if i2c[1];
    par
    {
        i2c_master(i2c, 1, p_i2c_scl, p_i2c_sda, 10);
        AudioHwRemote2(c, i2c[0]);
    }
}

unsafe chanend uc_audiohw;

static inline void CODEC_REGWRITE(unsigned reg, unsigned val)
{
    unsafe
    {
        uc_audiohw <: (unsigned) AUDIOHW_CMD_REGWR;
        uc_audiohw <: reg;
        uc_audiohw <: val;
    }
}

static inline void CODEC_REGREAD(unsigned reg, unsigned &val)
{
    unsafe
    {
        uc_audiohw <: (unsigned) AUDIOHW_CMD_REGRD;
        uc_audiohw <: reg;
        uc_audiohw :> val;
    }
}

/* Note this is called from tile[1] but the I2C lines to the CODEC are on tile[0]
 * use a channel to communicate CODEC reg read/writes to a remote core */
void AudioHwInit()
{
    unsigned regVal = 0;

    /* Take CODEC out of reset */
    p_codec_reset <: CODEC_RELEASE_RESET;

    delay_milliseconds(100);

    // Check we can talk to the CODEC
    CODEC_REGREAD(0x0b, regVal);

    assert(regVal == 1 && msg("CODEC reg read problem"));

    // Set register page to 0
    CODEC_REGWRITE(AIC3204_PAGE_CTRL, 0x00);

    // Initiate SW reset (PLL is powered off as part of reset)
    CODEC_REGWRITE(AIC3204_SW_RST, 0x01);

    // Program clock settings

    // Default is CODEC_CLKIN is from MCLK pin. Don't need to change this.
    // Power up NDAC and set to 1
    CODEC_REGWRITE(AIC3204_NDAC, 0x81);

    // Power up MDAC and set to 4
    CODEC_REGWRITE(AIC3204_MDAC, 0x84);

    // Power up NADC and set to 1
    CODEC_REGWRITE(AIC3204_NADC, 0x81);

    // Power up MADC and set to 4
     CODEC_REGWRITE(AIC3204_MADC, 0x84);

    // Program DOSR = 128
    CODEC_REGWRITE(AIC3204_DOSR, 0x80);

    // Program AOSR = 128
    CODEC_REGWRITE(AIC3204_AOSR, 0x80);

    // Set Audio Interface Config: I2S, 24 bits, slave mode, DOUT always driving.
    //   CODEC_REGWRITE(AIC3204_CODEC_IF, 0x20);
    CODEC_REGWRITE(AIC3204_CODEC_IF, 0x30);     // 32 bit mode
    // Program the DAC processing block to be used - PRB_P1
    CODEC_REGWRITE(AIC3204_DAC_SIG_PROC, 0x01);
    // Program the ADC processing block to be used - PRB_R1
    CODEC_REGWRITE(AIC3204_ADC_SIG_PROC, 0x01);
    // Select Page 1
    CODEC_REGWRITE(AIC3204_PAGE_CTRL, 0x01);
    // Enable the internal AVDD_LDO:
    CODEC_REGWRITE(AIC3204_LDO_CTRL, 0x09);
    //
    // Program Analog Blocks
    // ---------------------
    //
    // Disable Internal Crude AVdd in presence of external AVdd supply or before powering up internal AVdd LDO
    CODEC_REGWRITE(AIC3204_PWR_CFG, 0x08);
    // Enable Master Analog Power Control
    CODEC_REGWRITE(AIC3204_LDO_CTRL, 0x01);
    // Set Common Mode voltages: Full Chip CM to 0.9V and Output Common Mode for Headphone to 1.65V and HP powered from LDOin @ 3.3V.
    CODEC_REGWRITE(AIC3204_CM_CTRL, 0x33);
    // Set PowerTune Modes
    // Set the Left & Right DAC PowerTune mode to PTM_P3/4. Use Class-AB driver.
    CODEC_REGWRITE(AIC3204_PLAY_CFG1, 0x00);
    CODEC_REGWRITE(AIC3204_PLAY_CFG2, 0x00);
    // Set ADC PowerTune mode PTM_R4.
    CODEC_REGWRITE(AIC3204_ADC_PTM, 0x00);
    // Set MicPGA startup delay to 3.1ms
    CODEC_REGWRITE(AIC3204_AN_IN_CHRG, 0x31);
    // Set the REF charging time to 40ms
    CODEC_REGWRITE(AIC3204_REF_STARTUP, 0x01);
    // HP soft stepping settings for optimal pop performance at power up
    // Rpop used is 6k with N = 6 and soft step = 20usec. This should work with 47uF coupling
    // capacitor. Can try N=5,6 or 7 time constants as well. Trade-off delay vs �pop� sound.
    CODEC_REGWRITE(AIC3204_HP_START, 0x25);
    // Route Left DAC to HPL
    CODEC_REGWRITE(AIC3204_HPL_ROUTE, 0x08);
    // Route Right DAC to HPR
    CODEC_REGWRITE(AIC3204_HPR_ROUTE, 0x08);
    // We are using Line input with low gain for PGA so can use 40k input R but lets stick to 20k for now.
    // Route IN2_L to LEFT_P with 20K input impedance
    CODEC_REGWRITE(AIC3204_LPGA_P_ROUTE, 0x20);
    // Route IN2_R to LEFT_M with 20K input impedance
    CODEC_REGWRITE(AIC3204_LPGA_N_ROUTE, 0x20);
    // Route IN1_R to RIGHT_P with 20K input impedance
    CODEC_REGWRITE(AIC3204_RPGA_P_ROUTE, 0x80);
    // Route IN1_L to RIGHT_M with 20K input impedance
    CODEC_REGWRITE(AIC3204_RPGA_N_ROUTE, 0x20);
    // Unmute HPL and set gain to 0dB
    CODEC_REGWRITE(AIC3204_HPL_GAIN, 0x00);
    // Unmute HPR and set gain to 0dB
    CODEC_REGWRITE(AIC3204_HPR_GAIN, 0x00);
    // Unmute Left MICPGA, Set Gain to 0dB.
    CODEC_REGWRITE(AIC3204_LPGA_VOL, 0x00);
    // Unmute Right MICPGA, Set Gain to 0dB.
    CODEC_REGWRITE(AIC3204_RPGA_VOL, 0x00);
    // Power up HPL and HPR drivers
    CODEC_REGWRITE(AIC3204_OP_PWR_CTRL, 0x30);

    // Wait for 2.5 sec for soft stepping to take effect
    delay_milliseconds(2500);

    //
    // Power Up DAC/ADC
    // ----------------
    //
    // Select Page 0
    CODEC_REGWRITE(AIC3204_PAGE_CTRL, 0x00);
    // Power up the Left and Right DAC Channels. Route Left data to Left DAC and Right data to Right DAC.
    // DAC Vol control soft step 1 step per DAC word clock.
    CODEC_REGWRITE(AIC3204_DAC_CH_SET1, 0xd4);
    // Power up Left and Right ADC Channels, ADC vol ctrl soft step 1 step per ADC word clock.
    CODEC_REGWRITE(AIC3204_ADC_CH_SET, 0xc0);
    // Unmute Left and Right DAC digital volume control
    CODEC_REGWRITE(AIC3204_DAC_CH_SET2, 0x00);
    // Unmute Left and Right ADC Digital Volume Control.
    CODEC_REGWRITE(AIC3204_ADC_FGA_MUTE, 0x00);

    delay_milliseconds(1);

    // Set the AppPLL up to output MCLK.
    // Disable the PLL
    write_node_config_reg(tile[AUDIO_IO_TILE], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (APP_PLL_CTL_441 & 0xF7FFFFFF));
    // Enable the PLL to invoke a reset on the appPLL.
    write_node_config_reg(tile[AUDIO_IO_TILE], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_441);
    // Must write the CTL register twice so that the F and R divider values are captured using a running clock.
    write_node_config_reg(tile[AUDIO_IO_TILE], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_441);
    // Now disable and re-enable the PLL so we get the full 5us reset time with the correct F and R values.
    write_node_config_reg(tile[AUDIO_IO_TILE], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (APP_PLL_CTL_441 & 0xF7FFFFFF));
    write_node_config_reg(tile[AUDIO_IO_TILE], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_441);

    assert(DEFAULT_FREQ >= 22050);

    // Set the fractional divider if used
    if(DEFAULT_FREQ % 22050 == 0)
    {
        write_node_config_reg(tile[0], XS1_SSWITCH_SS_APP_PLL_FRAC_N_DIVIDER_NUM, APP_PLL_FRAC_44);
    }
    else
    {
        write_node_config_reg(tile[0], XS1_SSWITCH_SS_APP_PLL_FRAC_N_DIVIDER_NUM, APP_PLL_FRAC_48);
    }

    // Wait for PLL output frequency to stabilise due to fractional divider enable
    delay_microseconds(100);

    // Turn on the clock output
    write_node_config_reg(tile[0], XS1_SSWITCH_SS_APP_CLK_DIVIDER_NUM, APP_PLL_DIV);

    delay_milliseconds(1);

}

/* Configures the external audio hardware for the required sample frequency.
 * See gpio.h for I2C helper functions and gpio access
 */
void AudioHwConfig(unsigned samFreq, unsigned mClk, unsigned dsdMode,
    unsigned sampRes_DAC, unsigned sampRes_ADC)
{
    assert(samFreq >= 22050);

    // Set the AppPLL up to output MCLK.
    if ((samFreq % 22050) == 0)
    {
        // Disable the PLL
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (APP_PLL_CTL_441 & 0xF7FFFFFF));
        // Enable the PLL to invoke a reset on the appPLL.
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_441);
        // Must write the CTL register twice so that the F and R divider values are captured using a running clock.
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_441);
        // Now disable and re-enable the PLL so we get the full 5us reset time with the correct F and R values.
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (APP_PLL_CTL_441 & 0xF7FFFFFF));
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_441);

        // Set the fractional divider if used
        write_node_config_reg(tile[0], XS1_SSWITCH_SS_APP_PLL_FRAC_N_DIVIDER_NUM, APP_PLL_FRAC_44);
    }
    else if ((samFreq % 24000) == 0)
    {
        // Disable the PLL
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (APP_PLL_CTL_48 & 0xF7FFFFFF));
        // Enable the PLL to invoke a reset on the appPLL.
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_48);
        // Must write the CTL register twice so that the F and R divider values are captured using a running clock.
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_48);
        // Now disable and re-enable the PLL so we get the full 5us reset time with the correct F and R values.
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (APP_PLL_CTL_48 & 0xF7FFFFFF));
        write_node_config_reg(tile[1], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, APP_PLL_CTL_48);

        // Set the fractional divider if used
        write_node_config_reg(tile[0], XS1_SSWITCH_SS_APP_PLL_FRAC_N_DIVIDER_NUM, APP_PLL_FRAC_48);
    }

    // Wait for PLL output frequency to stabilise due to fractional divider enable
    delay_microseconds(100);

    // Turn on the clock output
    write_node_config_reg(tile[0], XS1_SSWITCH_SS_APP_CLK_DIVIDER_NUM, APP_PLL_DIV);
}

