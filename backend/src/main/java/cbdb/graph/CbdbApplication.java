package cbdb.graph;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cache.annotation.EnableCaching;

@SpringBootApplication
@EnableCaching
public class CbdbApplication {
    public static void main(String[] args) {
        SpringApplication.run(CbdbApplication.class, args);
    }
}
