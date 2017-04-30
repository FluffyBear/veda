extern crate rmp;

use std::io::Cursor;
use std::result;
use std::fmt;
use self::rmp::decode;
use std::io::{Write, stderr};

pub enum Type {
    ArrayObj,
    MapObj,
    StrObj,
    UintObj,
    IntObj,
    NilObj,
    ReservedObj,
    BoolObj,
    BinObj,
    ExtObj,
    FloatObj
}

fn decode_uint8(cursor: &mut Cursor<&[u8]>) -> u64 {
    return decode::read_u8(cursor).unwrap() as u64;
}

fn decode_uint16(cursor: &mut Cursor<&[u8]>) -> u64 {
    // writeln!(&mut stderr(), "marker = {:?}", marker); 
    return decode::read_u16(cursor).unwrap() as u64;
}

fn decode_uint32(cursor: &mut Cursor<&[u8]>) -> u64 {
    return decode::read_u32(cursor).unwrap() as u64;
}

fn decode_uint64(cursor: &mut Cursor<&[u8]>) -> u64 {
    return decode::read_u64(cursor).unwrap();
}

fn decode_pfix(cursor: &mut Cursor<&[u8]>, size: u8) -> u64 {
    let mut val: u64 = 0;
    // writeln!(stderr(), "DECODE PFIX {0}", size);
    for i in 0 .. size {
        // writeln!(stderr(), "DECODE BYTE {0}", size);
        let byte = decode::read_pfix(cursor).unwrap();
        val <<= 8;
        val |= byte as u64;
    }
    return val;   
}

pub fn decode_uint(cursor: &mut Cursor<&[u8]>) -> Result<u64, String> {
    let val: u64 = 0;
    let curr_position = cursor.position();
    // return Ok(decode::read_pfix(cursor).unwrap() as u64);
     
    let marker = decode::read_marker(cursor).unwrap();
    cursor.set_position(curr_position);
    // writeln!(&mut stderr(), "marker = {:?}", marker); 
    // rmp::Marker::FixPos();
    match marker {
        rmp::Marker::U8  => Ok(decode_uint8(cursor)),
        rmp::Marker::U16  => Ok(decode_uint16(cursor)),
        rmp::Marker::U32 => Ok(decode_uint32(cursor)),
        rmp::Marker::U64  => Ok(decode_uint64(cursor)),
        _ => match decode::read_pfix(cursor) {
            Ok(v)  => Ok(v as u64),
            Err(err) => Err(format!("@ERR IS NOT UINT {:?}", marker))
        }
    }
}

fn decode_int8(cursor: &mut Cursor<&[u8]>) -> i64 {
    return decode::read_i8(cursor).unwrap() as i64;
}

fn decode_int16(cursor: &mut Cursor<&[u8]>) -> i64 {
    // writeln!(&mut stderr(), "marker = {:?}", marker); 
    return decode::read_i16(cursor).unwrap() as i64;
}

fn decode_int32(cursor: &mut Cursor<&[u8]>) -> i64 {
    return decode::read_i32(cursor).unwrap() as i64;
}

fn decode_int64(cursor: &mut Cursor<&[u8]>) -> i64 {
    return decode::read_i64(cursor).unwrap();
}

pub fn decode_int(cursor: &mut Cursor<&[u8]>) -> Result<i64, String> {
    let curr_position = cursor.position();
    // return Ok(decode::read_pfix(cursor).unwrap() as u64);
     
    let marker = decode::read_marker(cursor).unwrap();
    cursor.set_position(curr_position);
    // writeln!(&mut stderr(), "marker = {:?}", marker); 
    // rmp::Marker::FixPos();
    match marker {
        rmp::Marker::I8  => Ok(decode_int8(cursor)),
        rmp::Marker::I16  => Ok(decode_int16(cursor)),
        rmp::Marker::I32 => Ok(decode_int32(cursor)),
        rmp::Marker::I64  => Ok(decode_int64(cursor)),
        _ => match decode::read_nfix(cursor) {
            Ok(v)  => Ok(v as i64),
            Err(_) => Err(format!("@ERR IS NOT INT {:?}", marker))
        }
    }
}

pub fn decode_bool(cursor: &mut Cursor<&[u8]>) -> Result<bool, String> {
    match decode::read_bool(cursor) {
        Ok(v) => Ok(v),
        Err(err) => Err(format!("@ERR IS NOT BOOL"))
    }
}

pub fn decode_array(cursor: &mut Cursor<&[u8]>) -> Result<u64, String> {
    return Ok(decode::read_array_len(cursor).unwrap() as u64);
    
   /* match decode::read_array_len(cursor) {
        Ok(arr_size) => Ok(arr_size as u64),
        Err(err) => Err(format!("@ERR DECODING ARRAY {0}", err))
    }*/
}

pub fn decode_nil(cursor: &mut Cursor<&[u8]>) -> Result<(), String> {
    match decode::read_nil(cursor) {
        Ok(arr_size) => Ok(()),
        Err(err) => Err(format!("@ERR DECODING NIL {0}", err))
    }
}

pub fn decode_string(cursor: &mut Cursor<&[u8]>, buf: &mut Vec<u8>) -> Result<(), String> {
    let mut len: usize = 0;
    let s = decode::read_str_ref(&cursor.get_ref()[cursor.position() as usize ..]).unwrap();
    decode::read_str_len(cursor).unwrap();
    let curr_position = cursor.position();
    cursor.set_position(curr_position + s.len() as u64);
    // writeln!(stderr(), "@CURR POS {0} : INNER LEN {1}", cursor.position(), 
    // cursor.get_ref()[..].len()); 
    *buf = s[..].to_vec();
    return Ok(());

    // writeln!(stderr(), "@PREV POS {0}", cursor.position());
    /*match decode::read_str_ref(&cursor.get_ref()[cursor.position() as usize ..]) {
        Ok(s) => {
            decode::read_str_len(cursor);
            let curr_position = cursor.position();
            cursor.set_position(curr_position + s.len() as u64);
            // writeln!(stderr(), "@CURR POS {0} : INNER LEN {1}", cursor.position(), 
                // cursor.get_ref()[..].len()); 
            *buf = s[..].to_vec();
            return Ok(());
        },
        Err(err) => Err(format!("@ERR DECODING STRING {0}", err))
    }*/
} 

pub fn decode_type(cursor: &mut Cursor<&[u8]>) -> Result<Type, String> {
    let curr_position = cursor.position();
    let result = decode::read_marker(cursor);
    cursor.set_position(curr_position);
    let mut marker: rmp::Marker;
    match result {
        Ok(m) => marker = m,
        Err(_) => return Err(format!("@ERR DECODING MARKER"))
    }
    // writeln!(stderr(), "@GET MARKER");
    // writeln!(&mut stderr(), "marker = {:?}", marker); 
    
    match marker.to_u8() {
        0x00 ... 0x7f => Ok(Type::UintObj),
        0xe0 ... 0xff => Ok(Type::IntObj),
        0x80 ... 0x8f => Ok(Type::MapObj),
        0x90 ... 0x9f => Ok(Type::ArrayObj),
        0xa0 ... 0xbf => Ok(Type::StrObj),
        0xc0 => Ok(Type::NilObj),
        // Marked in MessagePack spec as never used.
        0xc1 => Ok(Type::ReservedObj),
        0xc2 ... 0xc3 => Ok(Type::BoolObj),
        0xc4 ... 0xc6 => Ok(Type::BinObj),
        0xc7 ... 0xc9 => Ok(Type::ExtObj),
        0xca ... 0xcb => Ok(Type::FloatObj),
        0xcc ... 0xcf => Ok(Type::UintObj),
        0xd0 ... 0xd3 => Ok(Type::IntObj),
        0xd4 ... 0xd8 => Ok(Type::ExtObj),
        0xd9 ... 0xdb => Ok(Type::StrObj),
        0xdc ... 0xdd => Ok(Type::ArrayObj),
        0xde ... 0xdf => Ok(Type::ArrayObj),
        _ => return Err(format!("@UNSSUPPORTED TYPE {0}", marker.to_u8())),
    }
}

pub fn decode_map(cursor: &mut Cursor<&[u8]>) -> Result<u64, String> {
    match decode::read_map_len(cursor) {
        Ok(arr_size) => Ok(arr_size as u64),
        Err(err) => Err(format!("@ERR DECODING ARRAY {0}", err))
    }
}