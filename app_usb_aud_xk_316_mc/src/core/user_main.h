#ifndef USER_MAIN_H
#define USER_MAIN_H

#ifdef __XC__

#include "i2c.h"
#include <print.h>
#include <xs1.h>
#include <platform.h>

extern unsafe client interface i2c_master_if i_i2c_client;
extern void interface_saver(client interface i2c_master_if i);
extern void ctrlPort();

/* I2C interface ports */
extern port p_scl;
extern port p_sda;

#define USER_MAIN_DECLARATIONS \
    interface i2c_master_if i2c[1];

#define USER_MAIN_CORES on tile[0]: {\
                                        ctrlPort();\
                                        i2c_master(i2c, 1, p_scl, p_sda, 10);\
                                    }\
                        on tile[1]: {\
                                        unsafe\
                                        {\
                                            i_i2c_client = i2c[0];\
                                        }\
                                    }
#endif

#endif
