#ifndef MSGPACK8INDIVIDUAL_H
#define MSGPACK8INDIVIDUAL_H

#include <string>
#include <vector>
#include <map>
#include <iostream>
#include <msgpack.hpp>
#include "v8.h"

using namespace v8;
using namespace std;

typedef enum
{
    LANG_NONE = 0,
    LANG_RU   = 1,
    LANG_EN   = 2
} tLANG;

typedef enum ResourceType
{
    _Uri      = 1,
    _String   = 2,
    _Integer  = 4,
    _Datetime = 8,
    _Decimal  = 32,
    _Boolean  = 64
} tResourceType;

typedef enum ResourceOrigin
{
    _local    = 1,
    _external = 2
} tResourceOrigin;

struct Resource
{
    uint8_t type;
    uint8_t origin;
    uint8_t lang;

    string  str_data;
    bool    bool_data;
    int64_t long_data;
    int64_t decimal_mantissa_data;
    int64_t decimal_expanent_data;

    Resource () : type(0), origin(0), lang(0), long_data(0), decimal_mantissa_data(0), decimal_expanent_data(0), str_data (""), bool_data(false){};
};

struct Individual
{
    string                            uri;
    map < string, vector <Resource> > resources;
};

struct Element
{
    unsigned int    pos;
    string str;
    
    Element () : pos (0), str ("") {};
};

uint32_t write_individual(Individual *individual, char *in_buff);

void write_resources(string uri, vector <Resource> vv, msgpack::packer<msgpack::sbuffer> &pk);

int32_t msgpack2individual(Individual *individual, string in_str);

int32_t individual2msgpack(Individual *individual, char* in_buff);

#endif
