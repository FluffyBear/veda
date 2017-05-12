extern crate core;
extern crate rmp_bind;


use std;
use std::collections::HashMap;
use std::ffi::{ CStr };
use std::io::{ Write, stderr, Cursor };
use std::os::raw::c_char;
use std::ptr::null_mut;
use rmp_bind:: { decode, encode };
use super::authorization;

include!("../../module.rs");

#[derive(PartialEq, Eq, Copy)]
enum ResourceType {
    Uri = 1,
    Str = 2,
    Integer = 4,
    Datetime = 8,
    Decimal = 32,
    Boolean = 64
}

#[derive(PartialEq, Eq, Copy)]
enum Lang {
    LangNone = 0,
    LangRu  = 1,
    LangEn   = 2
}

#[derive(PartialEq, Eq)]
pub struct Resource {
    res_type: ResourceType,
    lang: Lang,
    pub str_data: Vec<u8>,
    bool_data: bool,
    long_data: i64,
    decimal_mantissa_data: i64,
    decimal_exponent_data: i64,
}

#[derive(Hash, Eq, PartialEq)]
struct Right {
    id: Vec<u8>,
    access: u8,
    is_deleted: bool
}

impl Clone for ResourceType {
    fn clone(&self) -> ResourceType {
        *self
    }
}

impl Clone for Lang {
    fn clone(&self) -> Lang {
        *self
    }
}

pub struct Individual {
    pub uri: Vec<u8>,
    pub resources: HashMap<String, Vec<Resource>>    
}

impl Resource {
    pub fn new() -> Resource {
        return Resource { res_type: ResourceType::Uri, lang: Lang::LangNone, str_data: Vec::default(),
            bool_data: false, long_data: 0, decimal_mantissa_data: 0, decimal_exponent_data: 0};
    }

    fn clone(&self) -> Resource {
        return Resource { res_type: self.res_type, lang: self.lang, str_data: self.str_data.clone(),
            bool_data: self.bool_data, long_data: self.long_data, 
            decimal_mantissa_data: self.decimal_mantissa_data, decimal_exponent_data: 
            self.decimal_exponent_data};
    }
}

impl Right {
    pub fn new() -> Right {
        return Right { id: Vec::default(), access: 0, is_deleted: false };
    } 
}

impl Individual {
    pub fn new() -> Individual {
        return Individual { uri: Vec::default(), resources: HashMap::new() };
    }
}

impl Lang {
    fn from_u64(val: u64) -> Lang {
        match val {
            1 => Lang::LangRu,
            2 => Lang::LangEn,
            _ => Lang::LangNone
        }
    } 
}

pub fn msgpack_to_individual(cursor: &mut Cursor<&[u8]>, individual: &mut Individual) -> Result<(), String> {
    let arr_size: u64;
    match decode::decode_array(cursor) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL MSGPACK ARRAY {0}", err)),
        Ok(size) => arr_size = size
    }

    if arr_size != 2 {
        return Err("@ERR INVALID INDIVIDUAL MSGPACK SIZE".to_string());    
    }

    match decode::decode_string(cursor, &mut individual.uri) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL URI {0}", err)),
        Ok(_) => {}
    }

    // writeln!(stderr(), "@INDIVIDUAL URI {0}", std::str::from_utf8(&individual.uri[..]).unwrap()).unwrap();

    let map_size: u64;
    match decode::decode_map(cursor) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL MAP {0}", err)),
        Ok(size) => map_size = size
    }

    // writeln!(stderr(), "@MAP LEN {0}", map_size);

    for _ in 0..map_size {
        let mut key: Vec<u8> = Vec::default();
        let mut resources: Vec<Resource> = Vec::new();

        match decode::decode_string(cursor, &mut key) {
            Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL URI {0}", err)),
            Ok(_) => {}
        }
        // writeln!(stderr(), "@RESOURCE KEY {0}", std::str::from_utf8(&key[..]).unwrap()).unwrap();
        
        let res_size: u64;
        match decode::decode_array(cursor) {
            Ok(rs) => res_size = rs,
            Err(err) => return Err(format!("@ERR DECODING RESOURCES ARRAY {0}", err))
        }

        // writeln!(stderr(), "@RESOURCE ARRAY LEN {0}", res_size);
        for _ in 0.. res_size {
            let objtype: decode::Type;
            match decode::decode_type(cursor) {
                Ok(t) => objtype = t,
                Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
            }

            match objtype {
                decode::Type::ArrayObj => {
                    let res_arr_size = decode::decode_array(cursor).unwrap();
                    // writeln!(stderr(), "@DECODE RES ARR 2").unwrap();
                    let res_type: u64;
                    match decode::decode_uint(cursor) {
                        Ok(rt) => res_type = rt,
                        Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
                    }
                    // writeln!(stderr(), "@RES TYPE {0}", res_type);
                    if res_arr_size == 2 {
                        if res_type == ResourceType::Datetime as u64 {
                            let mut datetime: i64 = 0;
                            let decode_type: decode::Type;                   
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    match decode::decode_uint(cursor) {
                                        Ok(dt) => datetime = dt as i64,
                                        Err(err) => return Err(format!("@ERR DECODING DATETIME {0}", err))
                                    }
                                }

                                decode::Type::IntObj => {
                                    match decode::decode_int(cursor) {
                                        Ok(dt) => datetime = dt,
                                        Err(err) => return Err(format!("@ERR DECODING DATETIME {0}", err))
                                    }
                                }

                                _ => {}
                            }
                            // writeln!(stderr(), "@DATETIME {0}", datetime);
                            let mut resource = Resource::new();
                            resource.res_type = ResourceType::Datetime;
                            resource.long_data = datetime;
                            resources.push(resource);
                        } else if res_type == ResourceType::Str as u64 {
                            let mut resource = Resource::new();
                            
                            let decode_type: decode::Type;
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::StrObj => 
                                    decode::decode_string(cursor, &mut resource.str_data).unwrap(),
                                decode::Type::NilObj => decode::decode_nil(cursor).unwrap(),
                                _ => return Err("@UNKNOWN TYPE IN STRING RESOURCE".to_string())
                            }
                            resource.lang = Lang::LangNone;
                            // writeln!(stderr(), "@STR DATA {0}", std::str::from_utf8(
                                    // &resource.str_data[..]).unwrap()).unwrap();
                            resources.push(resource);
                        } else {
                            return Err("@UNKNOWN RESOURCE TYPE".to_string());
                        }
                    } else if res_arr_size == 3 {
                        // writeln!(stderr(), "@DECODE RES ARR 3").unwrap();
                        if res_type == ResourceType::Decimal as u64 {
                            let mut resource = Resource::new();
                            
                            let mut decode_type: decode::Type;  
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODEING MANTISSA TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    resource.decimal_mantissa_data = decode::decode_uint(cursor).unwrap() as i64;
                                },
                                decode::Type::IntObj => {
                                    resource.decimal_mantissa_data = decode::decode_int(cursor).unwrap();
                                },
                                _ => return Err("@ERR UNSUPPORTED MANTISSA TYPE".to_string())
                            }
  
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODEING MANTISSA TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    resource.decimal_exponent_data = decode::decode_uint(cursor).unwrap() as i64;
                                },
                                decode::Type::IntObj => {
                                    resource.decimal_exponent_data = decode::decode_int(cursor).unwrap();
                                },
                                _ => return Err("@ERR UNSUPPORTED EXPONENT TYPE".to_string())
                            }

                            resource.res_type = ResourceType::Decimal;
                            resources.push(resource);
                        } else if res_type == ResourceType::Str as u64 {
                            let mut resource = Resource::new();

                            let decode_type: decode::Type;
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::StrObj => 
                                    decode::decode_string(cursor, &mut resource.str_data).unwrap(),
                                decode::Type::NilObj => decode::decode_nil(cursor).unwrap(),
                                _ => return Err("@UNKNOWN TYPE IN STRING RESOURCE".to_string())
                            }

                            match decode::decode_uint(cursor) {
                                Ok(l) => resource.lang = Lang::from_u64(l),
                                Err(err) => return Err(format!("@ERR DECODING LEN {0}", err))
                            }
                            resource.res_type = ResourceType::Str;
                            resources.push(resource);
                        }                     
                    }
                }
                decode::Type::StrObj => {
                    // writeln!(stderr(), "@DECODE STROBJ RESOURCE").unwrap();
                    let mut resource = Resource::new();
                    decode::decode_string(cursor, &mut resource.str_data).unwrap();
                    resource.res_type = ResourceType::Uri;
                    resources.push(resource);
                }
                decode::Type::UintObj => {
                    // writeln!(stderr(), "@DECODE UINTOBJ RESOURCE").unwrap();
                    let mut resource = Resource::new();
                    resource.long_data = decode::decode_uint(cursor).unwrap() as i64;
                    resource.res_type = ResourceType::Integer;
                    resources.push(resource);
                }
                decode::Type::IntObj => {
                    // writeln!(stderr(), "@DECODE INTOBJ RESOURCE");
                    let mut resource = Resource::new();
                    resource.long_data = decode::decode_int(cursor).unwrap();
                    resource.res_type = ResourceType::Integer;
                    resources.push(resource);
                }
                decode::Type::BoolObj => {
                    // writeln!(stderr(), "@DECODE BOOLOBJ RESOURCE");
                    let mut resource = Resource::new();
                    resource.bool_data = decode::decode_bool(cursor).unwrap();
                    resource.res_type = ResourceType::Boolean;
                    resources.push(resource);
                }
               _ => return Err("@UNSUPPORTED RESOURCE TYPE".to_string())
            }
        }

        individual.resources.insert(std::str::from_utf8(key.as_ref()).unwrap().to_string(), resources);
    }
    return Ok(());
}

pub fn get_rdf_types(uri: &Vec<u8>, rdf_types: &mut Vec<Vec<u8>>, conn: &super::TarantoolConnection) 
    -> Result<(), String> {
    // writeln!(stderr(), "@TRY GET RDF TYPES");
    let mut request = Vec::new();

    encode::encode_array(&mut request, 1);
    // writeln!(stderr(), "@REQ LEN {0}", request.len()).unwrap();
    encode::encode_string(&mut request, &std::str::from_utf8(uri).unwrap());
    // writeln!(stderr(), "@REQ LEN1 {0}", request.len()).unwrap();
    unsafe {
        let request_len = request.len() as isize;
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);

        let mut get_result: *mut BoxTuple = null_mut();
        let get_code = box_index_get(conn.rdf_types_space_id, conn.rdf_types_index_id,
           key_ptr_start, key_ptr_end, &mut get_result as *mut *mut BoxTuple);
       
        if get_code < 0 {
            writeln!(stderr(), "@ERR {0}",
                CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string()).unwrap();
            return Err("@ERR READING RDF TYPES".to_string());
        } else if get_result != null_mut() {
            // writeln!(stderr(), "@GET RDF TYPES");
            let tuple_size = box_tuple_bsize(get_result);
            let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
            box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);
            let mut uri: Vec<u8> = Vec::default();
            let mut cursor: Cursor<&[u8]> = Cursor::new(&tuple_buf[..]);
            let arr_size = decode::decode_array(&mut cursor).unwrap();
            decode::decode_string(&mut cursor, &mut uri).unwrap();
            // writeln!(stderr(), "@RDF TYPE URI {0}", std::str::from_utf8(&uri[..]).unwrap());
            for _ in 1 .. arr_size {
                let mut buf: Vec<u8> = Vec::default();
                decode::decode_string(&mut cursor, &mut buf).unwrap();
                rdf_types.push(buf);
            }
            
        }
    }

    // writeln!(stderr(), "@RETURN RDF TYPES");
    return Ok(());
}

pub fn put_rdf_types(uri: &Vec<u8>, rdf_types: &Vec<Resource>, conn: &super::TarantoolConnection) {
    let mut request = Vec::new();
    encode::encode_array(&mut request, rdf_types.len() as u32 + 1);
    // writeln!(stderr(), "@ENCODE URI {0}", std::str::from_utf8(uri.as_ref()).unwrap());
    encode::encode_string_bytes(&mut request, &uri);
    for i in 0 .. rdf_types.len() {
        encode::encode_string_bytes(&mut request, &rdf_types[i].str_data);
        // writeln!(stderr(), "@ENCODE RDF TYPE {0}", std::str::from_utf8(&rdf_types[i].str_data.as_ref()).unwrap());
    }

    unsafe {
        let request_len = request.len() as isize;
        // writeln!(stderr(), "@REPLACE REQ LEN {0}", request_len);
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);
        // writeln!(stderr(), "@TRY REPLACE RDF TYPES");
        let replace_code = box_replace(conn.rdf_types_space_id, key_ptr_start, key_ptr_end, 
            &mut null_mut() as *mut *mut BoxTuple);
        if replace_code < 0 {
            writeln!(stderr(), "@ERR PUT RDF TYPE {0}",
                CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string()).unwrap();
        }
        // writeln!(stderr(), "@REPLACE CODE {0}", replace_code);
    }
}

fn peek_from_tarantool(key: &str, new_right_set: &mut HashMap<String, Right>, 
    space_id: u32, index_id: u32) {
    unsafe {
        let mut request = Vec::new();
        encode::encode_array(&mut request, 1);
        encode::encode_string(&mut request, key);

        let request_len = request.len() as isize;
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);

        let mut get_result: *mut BoxTuple = std::mem::uninitialized();
        // writeln!(stderr(), "PEEK FROM {0} {1}", space_id, index_id);
        let get_code = box_index_get(space_id, index_id, key_ptr_start, key_ptr_end, 
            &mut get_result as *mut *mut BoxTuple);

        if get_code < 0 {
            writeln!(stderr(), "@ERR PEEK RIGHTS FROM TARANTOOL {0}",
                CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string()).unwrap();
        } else if get_result != null_mut() {
            let tuple_size = box_tuple_bsize(get_result);
            let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
            box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);
            let mut cursor = Cursor::new(&tuple_buf[..]);

            let arr_size = decode::decode_array(&mut cursor).unwrap();
            // writeln!(stderr(), "@PEEK RIGHTS ARR LEN {0}", arr_size);
            
            let mut right_uri: Vec<u8> = Vec::default();
            decode::decode_string(&mut cursor, &mut right_uri).unwrap();
            // writeln!(stderr(), "@PEEK RIGHT URI {0}", std::str::from_utf8(&right_uri[..]).unwrap());

            let mut i = 1;
            while i < arr_size {
                let mut right: Right = Right::new();
                decode::decode_string(&mut cursor, &mut right.id).unwrap();
                // writeln!(stderr(), "@RIGHT ID {0}", std::str::from_utf8(&right.id[..]).unwrap());
                right.access = decode::decode_uint(&mut cursor).unwrap() as u8;
                // writeln!(stderr(), "@RIGHT ACCESS {0}", right.access);
                new_right_set.insert(std::str::from_utf8(&right.id[..]).unwrap().to_string(), right);
                i += 2;
            }
        } 
    }
}

fn push_into_tarantool(key: &str, new_right_set: &HashMap<String, Right>, space_id: u32, index_id: u32) {
    let mut arr_size = new_right_set.len() * 2 + 1;
    // iterate over everything.
    // writeln!(stderr(), "@NEW RIGHT SET LEN {0}", new_right_set.len());
    for (_, right) in new_right_set {
        if right.is_deleted {
            arr_size -= 2;
        }
    }

    let mut request = Vec::new();
    // writeln!(stderr(), "@REQUEST ARR LEN {0}", arr_size);
    encode::encode_array(&mut request, arr_size as u32);
    // writeln!(stderr(), "@REQUEST KEY {0}", key);    
    encode::encode_string(&mut request, key);
    for (_, right) in new_right_set {
        if !right.is_deleted {
            // writeln!(stderr(), "@PUSH RIGHT ID {0}", right_id);
            encode::encode_string_bytes(&mut request, &right.id);
            encode::encode_uint(&mut request, right.access as u64);
        }
    }

    unsafe {
        let request_len = request.len() as isize;
        // writeln!(stderr(), "@REPLACE REQ LEN {0}", request_len);
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);

        if arr_size > 1 {
            // writeln!(stderr(), "@REPLACE RIGHT SET");
            let replace_code = box_replace(space_id, key_ptr_start, key_ptr_end, 
            &mut null_mut() as *mut *mut BoxTuple);
            if replace_code < 0 {
                writeln!(stderr(), "@ERR PUT RIGHT SET {0}",
                    CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string()).unwrap();
            }
        } else {
            // writeln!(stderr(), "@DELETE RIGHT SET");
            let delete_code = box_delete(space_id, index_id, key_ptr_start, key_ptr_end, 
                &mut null_mut() as *mut *mut BoxTuple);
            if delete_code < 0 {
                writeln!(stderr(), "@ERR DELETE RIGHT SET {0}",
                    CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string()).unwrap();
            }
        }
    }
}

fn update_right_set(resource: &Vec<Resource>, in_set: &Vec<Resource>, is_deleted: bool, 
    space_id: u32, index_id: u32, access: u8) {
    for i in 0 .. resource.len() {
        let mut new_right_set: HashMap<String, Right> = HashMap::new(); 
        let key: &str = std::str::from_utf8(&resource[i].str_data[..]).unwrap();
        // writeln!(stderr(), "@RIGHT KEY {0}", key);        
        peek_from_tarantool(key, &mut new_right_set, space_id, index_id);
        // writeln!(stderr(), "@PEEK LEN {0}", new_right_set.len());
        for j in 0 .. in_set.len() {
            let in_set_key = std::str::from_utf8(&in_set[j].str_data[..]).unwrap();
            // writeln!(stderr(), "@RIGHT IN SET KEY {0}", in_set_key);
            if new_right_set.contains_key(in_set_key) {
                let right = new_right_set.get_mut(in_set_key).unwrap();
                right.is_deleted = is_deleted;
                right.access |= access;
            } else {
                let right = Right { id: in_set_key.as_bytes().to_vec(), access: access, 
                        is_deleted: is_deleted };
                new_right_set.insert(in_set_key.to_string(), right);
            }
       }
        push_into_tarantool(&key, &new_right_set, space_id, index_id);       
    }
}

pub fn prepare_right_set(prev_state: &Individual, new_state: &Individual, p_resource: &str, 
    p_in_set: &str, space_id: u32, index_id: u32) -> Result<(), String> {
    let mut is_deleted = false;
    let mut access: u8 = 0;

    match new_state.resources.get(&"v-s:deleted".to_string()) {
        Some(res) => is_deleted = res[0].bool_data,
        _ => {}
    }

    match new_state.resources.get(&"v-s:canCreate".to_string()) {
        Some(res) => {
            if res[0].bool_data {
                access |= authorization::ACCESS_CAN_CREATE; 
            } else {
                access |= authorization::ACCESS_CAN_NOT_CREATE;
            }
        },
        _ => {}
    }

    match new_state.resources.get(&"v-s:canRead".to_string()) {
        Some(res) => {
            if res[0].bool_data {
                access |= authorization::ACCESS_CAN_READ; 
            } else {
                access |= authorization::ACCESS_CAN_NOT_READ;
            }
        },
        _ => {}
    }

    match new_state.resources.get(&"v-s:canUpdate".to_string()) {
        Some(res) => {
            if res[0].bool_data {
                access |= authorization::ACCESS_CAN_UPDATE; 
            } else {
                access |= authorization::ACCESS_CAN_NOT_UPDATE;
            }
        },
        _ => {}
    }

    match new_state.resources.get(&"v-s:canDelete".to_string()) {
        Some(res) => {
            if res[0].bool_data {
                access |= authorization::ACCESS_CAN_DELETE; 
            } else {
                access |= authorization::ACCESS_CAN_NOT_DELETE;
            }
        },
        _ => {}
    }

    access = if access > 0 { access } else { authorization::DEFAULT_ACCESS };
    // writeln!(stderr(), "@IS DELETED {0}", is_deleted);
    let new_resource = new_state.resources.get(p_resource).unwrap();
    let new_in_set = new_state.resources.get(p_in_set).unwrap();
    
    let mut prev_resource = &Vec::default();    
    match prev_state.resources.get(p_resource) {
        Some(res) => prev_resource = res,
        _ => {}
    }

    let mut delta: Vec<Resource> = Vec::default();
    get_delta(prev_resource, new_resource, &mut delta);
    // writeln!(stderr(), "@RES LENS {0} {1}", new_resource.len(), delta.len());    
    update_right_set(new_resource, new_in_set, is_deleted, space_id, index_id, access);
    if delta.len() > 0 {
        update_right_set(&delta, new_in_set, true, space_id, index_id, access);
    }
    
    return Ok(());
}

fn get_delta(a: &Vec<Resource>, b: &Vec<Resource>, delta: &mut Vec<Resource>) {
    let vec_len = a.len();
    for i in 0 .. vec_len {
        let mut j = 0;
        while j < b.len() {
            if a[i] == b[j] {
                break;
            }
            j += 1;
        }

        if j == b.len() {
            delta.push(a[i].clone());
        }
    }
}