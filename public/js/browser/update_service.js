/**

Update service for individuals that were changed on server

 */

veda.Module(function UpdateService(veda) { "use strict";

  veda.UpdateService = function () {

    // Singleton pattern
    if (veda.UpdateService.prototype._singletonInstance) {
      return veda.UpdateService.prototype._singletonInstance;
    }
    veda.UpdateService.prototype._singletonInstance = this;

    var self = riot.observable(this);

    var address = "ws://" + location.hostname + ":8088/ccus",
        socket,
        msgInterval,
        msgDelay = 1000,
        connectTimeout,
        connectDelay = Math.round(5000 + 5000 * Math.random()),
        maxConnectDelay = 30000,
        connectTries = -1,
        list = {},
        delta = {};

    this.list = function () {
      return list;
    }

    this.synchronize = function() {
      clearInterval(msgInterval);
      msgInterval = undefined;
      list = {};
      delta = {};
      if (socket && socket.readyState === 1) {
        socket.send("=");
        //console.log("client -> server: =");
      }
    }

    this.subscribe = function(uri) {
      if (list[uri]) {
        ++list[uri].subscribeCounter;
        return;
      }
      var individual = new veda.IndividualModel(uri);
      var updateCounter = individual.hasValue("v-s:updateCounter") ? individual["v-s:updateCounter"][0] : 0;
      list[uri] = {
        subscribeCounter: 1,
        updateCounter: updateCounter
      };
      delta[uri] = {
        operation: "+",
        updateCounter: updateCounter
      };
      if (!msgInterval) {
        msgInterval = setInterval(pushDelta, msgDelay);
      }
    }

    this.unsubscribe = function (uri) {
      if (uri === "*") {
        clearInterval(msgInterval);
        msgInterval = undefined;
        list = {};
        delta = {};
        if (socket && socket.readyState === 1) {
          socket.send("-*");
          //console.log("client -> server: -*");
        }
      } else {
        if ( !list[uri] ) {
          return;
        } else if ( list[uri].subscribeCounter === 1 ) {
          delete list[uri];
          delta[uri] = {
            operation: "-"
          };
          if (!msgInterval) {
            msgInterval = setInterval(pushDelta, msgDelay);
          }
        } else {
          --list[uri].subscribeCounter;
          return;
        }
      }
    }

    function pushDelta() {
      var subscribe = [],
          unsubscribe = [],
          subscribeMsg,
          unsubscribeMsg;
      for (var uri in delta) {
        if (delta[uri].operation === "+") {
          subscribe.push("+" + uri + "=" + delta[uri].updateCounter);
        } else {
          unsubscribe.push("-" + uri);
        }
      }
      subscribeMsg = subscribe.join(",");
      unsubscribeMsg = unsubscribe.join(",");
      delta = {};
      if (socket && socket.readyState === 1 && subscribeMsg) {
        socket.send(subscribeMsg);
        //console.log("client -> server:", subscribeMsg);
      }
      if (socket && socket.readyState === 1 && unsubscribeMsg) {
        socket.send(unsubscribeMsg);
        //console.log("client -> server:", unsubscribeMsg);
      }
      clearInterval(msgInterval);
      msgInterval = undefined;
    }

    socket = initSocket();

    return this;

    function initSocket () {
      var socket = new WebSocket(address);
      socket.onopen = openedHandler;
      socket.onclose = closedHandler;
      socket.onerror = errorHandler;
      socket.onmessage = messageHandler;
      return socket;
    }

    function openedHandler(event) {
      if (connectTries >= 0) { veda.trigger("success", {status: "WS: Соединение восстановлено"}) }
      //console.log("client: websocket opened");
      connectTries = -1;
      var msg = "ccus=" + veda.ticket;
      if (socket && socket.readyState === 1) {
        //Handshake
        socket.send(msg);
        //console.log("client -> server:", msg);
      }
      var uris = Object.keys(list);
      self.synchronize();
      uris.map(self.subscribe);
      /*uris.map(function (uri) {
        var i = new veda.IndividualModel(uri);
        if ( !i.isSync() && !i.isNew() && !i.hasValue("v-s:isDraft", true) ) {
          i.reset();
        }
        self.subscribe(uri);
      });*/
    }

    function closedHandler(event) {
      if (connectDelay * connectTries < maxConnectDelay) { connectTries++ }
      veda.trigger("danger", {status: "WS: Соединение прервано"});
      //console.log("client: websocket closed,", "re-connect in", Math.round(connectDelay * connectTries / 1000), "secs" );
      connectTimeout = setTimeout(function () {
        socket = initSocket();
      }, connectDelay * connectTries);
    }

    function errorHandler(event) {
      //veda.trigger("danger", {status: "WS: Ошибка соединения"});
      //console.log("client: websocket error");
    }

    function messageHandler(event) {
      var msg = event.data,
          uris;
      //console.log("server -> client:", msg);
      if (msg.indexOf("=") === 0) {
        uris = msg.substr(1);
      } else {
        uris = msg;
      }
      if (uris.length === 0) {
        return;
      }
      uris = uris.split(",");
      for (var i = 0; i < uris.length; i++) {
        try {
          var tmp = uris[i].split("="),
              uri = tmp[0],
              updateCounter = parseInt(tmp[1]),
              individual = new veda.IndividualModel(uri),
              list = self.list();
          list[uri] = list[uri] ? {
            subscribeCounter: list[uri].subscribeCounter,
            updateCounter: updateCounter
          } : {
            subscribeCounter: 1,
            updateCounter: updateCounter
          };
          if ( !individual.hasValue("v-s:updateCounter", updateCounter) && !individual.hasValue("v-s:isDraft", true) ) {
            individual.reset();
          }
        } catch (e) {
          //console.log("error: individual update service failed for id =", uri, e);
        }
      }
    }

  }

});
