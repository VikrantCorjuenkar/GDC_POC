public class HelloWorld {
    public static String sayHello() {

        for(Integer i = 0; i < 10; i++) {
            List<Account> accList = [SELECT Id FROM Account];
            System.debug('Hello World, please follow salesforce best practices...');
        }
        return 'Hello World, please follow salesforce best practices...';

    }
}