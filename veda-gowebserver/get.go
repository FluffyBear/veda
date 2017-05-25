package main

import (
	"encoding/json"
	"log"

	"github.com/valyala/fasthttp"
)

func getIndividual(ctx *fasthttp.RequestCtx) {
	var uri string
	var ticketKey string
	var ticket ticket

	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	uri = string(ctx.QueryArgs().Peek("uri")[:])

	if len(uri) == 0 || ticketKey == "" {
		log.Println("@ERR GET_INDIVIDUAL: ZERO LENGTH TICKET OR URI")
		ctx.Response.SetStatusCode(int(BadRequest))
		return
	}

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	_, ok := ontologyCache[uri]
	if ok {
		ctx.Write(ontologyCache[uri])
		ctx.Response.SetStatusCode(int(Ok))
		return
	}

	rr := conn.Get(true, ticket.UserURI, []string{uri}, false)
	if rr.CommonRC != Ok {
		log.Println("@ERR GET_INDIVIDUAL: GET INDIVIDUAL COMMON ", rr.CommonRC)
		ctx.Response.SetStatusCode(int(rr.CommonRC))
		return
	} else if rr.OpRC[0] != Ok {
		ctx.Response.SetStatusCode(int(rr.OpRC[0]))
		return
	} else {
		individual := MsgpackToMap(rr.Msgpaks[0])
		if individual == nil {
			log.Println("@ERR GET_INDIVIDUAL: DECODING INDIVIDUAL")
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}

		individualJSON, err := json.Marshal(individual)
		if err != nil {
			log.Println("@ERR GET_INDIVIDUAL: ENCODING INDIVIDUAL TO JSON ", err)
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}

		tryStoreInOntologyCache(individual["@"].(string), individual["rdf:type"].([]interface{}), individualJSON)
		ctx.Write(individualJSON)
	}

	ctx.Response.SetStatusCode(int(Ok))
	return
}

func getIndividuals(ctx *fasthttp.RequestCtx) {
	var jsonData map[string]interface{}
	var uris []string
	var ticketKey string
	var ticket ticket

	err := json.Unmarshal(ctx.Request.Body(), &jsonData)
	if err != nil {
		log.Println("@ERR GET_INDIVIDUALS: DECODING JSON REQUEST ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ticketKey = jsonData["ticket"].(string)

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	uris = make([]string, len(jsonData["uris"].([]interface{})))
	for i := 0; i < len(jsonData["uris"].([]interface{})); i++ {
		uris[i] = jsonData["uris"].([]interface{})[i].(string)
	}

	rr := conn.Get(true, ticket.UserURI, uris, false)
	if rr.CommonRC != Ok {
		log.Println("@ERR GET_INDIVIDUALS: GET COMMON ", rr.CommonRC)
		ctx.Response.SetStatusCode(int(rr.CommonRC))
		return
	}

	individuals := make([]interface{}, 0, len(rr.Msgpaks))
	for i := 0; i < len(rr.Msgpaks); i++ {
		if rr.OpRC[0] == Ok {
			individual := MsgpackToMap(rr.Msgpaks[0])
			if individual == nil {
				log.Println("@ERR GET_INDIVIDUALS: DECODING INDIVIDUAL")
				ctx.Response.SetStatusCode(int(InternalServerError))
				return
			}
			individuals = append(individuals, individual)

		}

		if err != nil {
			log.Println("@ERR ENCODING INDIVIDUAL TO JSON ", err)
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}

	}
	individualsJSON, err := json.Marshal(individuals)
	if err != nil {
		log.Println("@ERR GET_INDIVIDUALS: ENCODING INDIVIDUALS JSON ", err)
	}
	ctx.Write(individualsJSON)
	ctx.Response.SetStatusCode(int(Ok))
	return
}