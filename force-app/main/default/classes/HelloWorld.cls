public class HelloWorld {
    public static String sayHello() {

        for(Integer i = 0; i < 10;i++){
            List<Account> accounts = [SELECT Id, Name FROM Account];
            System.debug('Running a test');
        }

        return 'Hello World';
    }
}