var basic = require('./basic.js'),
    delegationRequest = require('./delegationRequest.js'),
    person = require('./person.js'),
    timeStamp = ''+Math.round(+new Date()/1000);

/**
 * Поиск элементов
 * @param driver
 * @param somethingUnique - элемент
 * @param count - количество, которое должно быть после поиска
 * @param phase - текуща фаза теста
 */

function check(driver, somethingUnique, count, phase) {
    basic.execute(driver, 'click', 'a[id="params-pill-ft"]', "****** PHASE#" + phase + " : ERROR = Cannot click on 'params-pill-ft' button");
    basic.execute(driver, 'sendKeys', 'h4[about="v-fs:EnterQuery"]+div[class="form-group"] input',
        "****** PHASE#" + phase + " : ERROR = Cannot input search request", somethingUnique);
    driver.wait
    (
        function () {
            driver.findElement({css:'h4[about="v-fs:EnterQuery"]+div[class="form-group"] button[id="submit"]'}).click();
            driver.sleep(basic.FAST_OPERATION);
            return driver.findElement({css:'span[href="#params-ft"]+span[class="badge"]'}).getText().then(function (txt) {
                return txt == count;
            });
        },
        basic.EXTRA_SLOW_OPERATION
    ).thenCatch(function (e) {basic.errorHandler(e, "****** PHASE#" + phase + " : ERROR = Number of documents is incorrect, expected: " + count);});
}

/**
 * 0.Open page -> login(as karpovrt)
 * 1.Create person1 -> Logout
 * 2.Login(as bychinat) -> Check number of persons(0) -> Logout;
 * 3.Login(as kaprovrt) -> Create delegation request -> Logout;
 * 4.Login(as bychinat) -> Check number of persons(1) -> Logout;
 *
 * 0.Открываем страницу -> Входим в систему под karpovrt;
 * 1.Создаем Персону1 -> Выходи из системы;
 * 2.Входим в систему под bychinat -> Проверяем, что в поиске не ищется наша Персона1 -> Выходим из системы;
 * 3.Входим в систему под karpovrt -> Создаем делегирование -> Выходим из системы;
 * 4.Входим в систему под bychinat -> Проверяем, что после делегирования наша Персона1 ищется -> Выходим из системы;
 */

basic.getDrivers().forEach(function (drv) {
    //PHASE#0: Login
    var driver = basic.getDriver(drv);
    basic.openPage(driver, drv);
    basic.login(driver, 'karpovrt', '123', '2', 'Администратор2', 0);

    //PHASE#1: Create person
    var now = new Date();
    person.createPerson(driver, drv, 'Bourne', 'Jason', timeStamp,
        ('0' + now.getDate()).slice(-2) + '.' + ('0' + (now.getMonth() + 1)).slice(-2) + '.' + now.getFullYear(), 1);
    basic.logout(driver, 1);

    //PHASE#2: Check person
    basic.login(driver, 'bychinat', '123', '4', 'Администратор4', 2);
    basic.openFulltextSearchDocumentForm(driver, 'Персона', 'v-s:Person', 2);
    check(driver,timeStamp, 0, 2);
    basic.logout(driver, 2);

    //PHASE#3: Delegation request
    basic.login(driver, 'karpovrt', '123', '2', 'Администратор2', 3);
    delegationRequest.createRequestDelegation(driver, 'Администратор4', 'Администратор4 : Аналитик', "td:Analyst1", 3);
    driver.sleep(basic.FAST_OPERATION);
    basic.execute(driver, 'click', 'a[href="#/v-l:Welcome"]', "****** PHASE#3 : ERROR = Cannot click on 'Welcome' button");
    basic.logout(driver, 3);

    //PHASE#4: Check person
    basic.login(driver, 'bychinat', '123', '4', 'Администратор4', 4);
    basic.openFulltextSearchDocumentForm(driver, 'Персона', 'v-s:Person', 4);
    check(driver, timeStamp, 1, 4);
    driver.quit();
});