// Document Model

"use strict";

function DocumentModel(veda, individual, container, template) {

	var self = individual instanceof IndividualModel ? individual : new IndividualModel(veda, individual);

	self.on("individual:loaded", function (_individual, _container) {
		veda.trigger("document:loaded", self, container, template);
	});
	
	veda.trigger("document:loaded", self, container, template);

	return self;
};
