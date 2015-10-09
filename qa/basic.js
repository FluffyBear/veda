var webdriver = require('selenium-webdriver'),
    FAST_OPERATION = 2000, 			// 2000ms  = 2sec  - time limit for fast operations 
	SLOW_OPERATION = 10000,			// 10000ms = 10sec - time limit for fast operations
	EXTRA_SLOW_OPERATION = 60000,	// 30000ms = 30sec - time limit for extra slow operations
	SERVER_ADDRESS = 'http://127.0.0.1:8080/';

webdriver.promise.controlFlow().on('uncaughtException', function(e) {
	console.trace(e);
});

module.exports = {
	FAST_OPERATION: FAST_OPERATION,
	SLOW_OPERATION: SLOW_OPERATION,
	EXTRA_SLOW_OPERATION: EXTRA_SLOW_OPERATION,
	openPage: function (driver, path) {
		if (path === undefined) {
			driver.get(SERVER_ADDRESS); 
		} else {
			driver.get(SERVER_ADDRESS+path);
		}
	},
	/**
	 * @param login - логин пользователя
	 * @param password - пароль пользователя
	 * @param assertUserFirstName - имя пользователя (для проверки коректности входа)
	 * @param assertUserLastName - фамилия пользователя (для проверки коректности входа)
	 */
	login: function (driver, login, password, assertUserFirstName, assertUserLastName) {
		// Вводим логин и пароль 
		driver.findElement({id:'login'}).sendKeys(login);
		driver.findElement({id:'password'}).sendKeys(password);
		driver.findElement({id:'submit'}).click();
		
		// Проверям что мы залогинены корректно
		driver.wait
		(
		  webdriver.until.elementTextContains(driver.findElement({id:'user-info'}), assertUserFirstName),
		  FAST_OPERATION
		);
		driver.wait
		(
		  webdriver.until.elementTextContains(driver.findElement({id:'user-info'}), assertUserLastName),
		  FAST_OPERATION
		);
	},
	/**
	 * Заполнить ссылочный атрибут значением из выпадающего списка 
	 * 
	 * @param atribute - rdf:type атрибута, который будет заполнятся выбором из выпадающего списка
	 * @param valueToSearch - значение, которое будет введено в строку поиска
	 * @param valueToChoose - значение, которое будет выбрано как результат поиска (без учёта регистра; если не указано, будет использовано значение value)
	 */
	chooseFromDropdown: function(driver, attribute, valueToSearch, valueToChoose) {
		driver.findElement({css:'div[rel="'+attribute+'"] + veda-control input[id="fulltext"]'}).sendKeys(valueToSearch);
		
		// Проверяем что запрашивамый объект появился в выпадающем списке
		driver.wait
		(
		  function () {
			  return driver.findElements({css:'div[rel="'+attribute+'"] + veda-control.fulltext div.tt-suggestion>p'}).then(function (suggestions) {
				  return webdriver.promise.filter(suggestions, function(suggestion) {
						return suggestion.getText().then(function(txt){ return txt.toLowerCase() == valueToChoose.toLowerCase() });
				  }).then(function(x) { return x.length>0; });
			  });
		  },
		  FAST_OPERATION
		);
		
		// Кликаем на запрашиваемый тип в выпавшем списке		
		driver.findElements({css:'div[rel="'+attribute+'"] + veda-control.fulltext div.tt-suggestion>p'}).then(function (suggestions) {
			
			webdriver.promise.filter(suggestions, function(suggestion) {				
				return suggestion.getText().then(function(txt){
					if (valueToChoose == undefined) {
						return txt.toLowerCase() == valueToSearch.toLowerCase();
					} else {
						return txt.toLowerCase() == valueToChoose.toLowerCase();
					}
				});
			}).then(function(x) { x[0].click();});
		});
	},
	/**
	 * Открыть форму создания документа определённого шаблона
	 * 
	 * @param templateName - имя шаблона, документ которого создается
	 * @param templateRdfType - rdf:type шаблона, документ которого создается
	 */
	openCreateDocumentForm: function (driver, templateName, templateRdfType) {
		// Клик `Документ` в главном меню
		driver.findElement({css:'li[resource="v-m:DocMenu"]'}).click();

		// Проверяем что открылось подменю 
		driver.wait
		(
		  webdriver.until.elementIsVisible(driver.findElement({css:'li[resource="v-m:Create"]'})),
		  FAST_OPERATION
		);

		// Клик `Создать`
		driver.findElement({css:'li[resource="v-m:Create"]'}).click();

		// Проверяем что открылась страница создания документов
		driver.wait
		(
		  webdriver.until.elementIsVisible(driver.findElement({css:'div[resource="v-fc:Create"]'})),
		  FAST_OPERATION
		);

		// Вводим запрашиваемый тип документа
		driver.findElement({id:'fulltext'}).sendKeys(templateName);

		// Проверяем что запрашиваемый тип появился в выпадающем списке
		driver.wait
		(
		  function () {
			  return driver.findElements({css:'veda-control.fulltext div.tt-suggestion>p'}).then(function (suggestions) {
				  return webdriver.promise.filter(suggestions, function(suggestion) {
						return suggestion.getText().then(function(txt){ return txt == templateName });
				  }).then(function(x) { return x.length>0; });
			  });
		  },
		  FAST_OPERATION
		);

		// Кликаем на запрашиваемый тип в выпавшем списке
		driver.findElements({css:'veda-control.fulltext div.tt-suggestion>p'}).then(function (suggestions) {
			webdriver.promise.filter(suggestions, function(suggestion) {
				return suggestion.getText().then(function(txt){ return txt == templateName });
			}).then(function(x) { x[0].click();});
		});
		
		// Проверяем что тип появился на экране
		driver.wait
		(
		  webdriver.until.elementIsVisible(driver.findElement({css:'span[about="'+templateRdfType+'"]'})),
		  FAST_OPERATION
		);
	},	
	/**
	 * Открыть форму полнотекстового поиска, при этом выбрать поиск внутри определённого шаблона
	 * 
	 * @param templateName - имя шаблона, документ которого ищется
	 * @param templateRdfType - rdf:type шаблона, документ которого ищется
	 */
	openFulltextSearchDocumentForm: function (driver, templateName, templateRdfType) {
		// Клик `Документ` в главном меню
		driver.findElement({css:'li[resource="v-m:DocMenu"]'}).click();

		// Проверяем что открылось подменю 
		driver.wait
		(
		  webdriver.until.elementIsVisible(driver.findElement({css:'li[resource="v-m:Find"]'})),
		  FAST_OPERATION
		);

		// Клик `Поиск`
		driver.findElement({css:'li[resource="v-m:Find"]'}).click();

		// Проверяем что открылась страница поиска
		driver.wait
		(
		  webdriver.until.elementIsVisible(driver.findElement({css:'div[resource="v-fs:Search"]'})),
		  FAST_OPERATION
		);

		// Вводим запрашиваемый тип документа
		driver.findElement({css:'div[typeof="v-fs:FulltextRequest"] input[id="fulltext"]'}).sendKeys(templateName);
		
		// Проверяем что запрашиваемый тип появился в выпадающем списке
		driver.wait
		(
		  function () {
			  return driver.findElements({css:'veda-control.fulltext div.tt-suggestion>p'}).then(function (suggestions) {
				  return webdriver.promise.filter(suggestions, function(suggestion) {
						return suggestion.getText().then(function(txt){ return txt == templateName });
				  }).then(function(x) { return x.length>0; });
			  });
		  },
		  FAST_OPERATION
		);
		
		// Кликаем на запрашиваемый тип в выпавшем списке
		driver.findElements({css:'veda-control.fulltext div.tt-suggestion>p'}).then(function (suggestions) {
			webdriver.promise.filter(suggestions, function(suggestion) {
				return suggestion.getText().then(function(txt){ return txt == templateName });
			}).then(function(x) { x[0].click();});
		});
		
		// Проверяем что тип появился на экране
		driver.wait
		(
		  webdriver.until.elementIsVisible(driver.findElement({css:'div[rel="v-fs:typeToSearch"] span[resource="'+templateRdfType+'"]'})),
		  FAST_OPERATION
		);
	}
};