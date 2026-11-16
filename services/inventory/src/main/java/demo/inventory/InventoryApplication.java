package demo.inventory;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Inventory service: in-memory stock levels with simulated latency and failures.
 * Intentionally uninstrumented -- OpenTelemetry is expected to be auto-injected.
 */
@SpringBootApplication
@RestController
public class InventoryApplication {

    private static final Logger log = LoggerFactory.getLogger(InventoryApplication.class);
    private static final int RESTOCK_LEVEL = 1000;

    private final Map<String, Integer> stock = new ConcurrentHashMap<>(Map.of(
            "sku-apple", RESTOCK_LEVEL,
            "sku-banana", RESTOCK_LEVEL,
            "sku-cherry", RESTOCK_LEVEL,
            "sku-durian", 25));

    public static void main(String[] args) {
        SpringApplication.run(InventoryApplication.class, args);
    }

    @GetMapping("/healthz")
    public Map<String, Boolean> healthz() {
        return Map.of("ok", true);
    }

    @GetMapping("/inventory")
    public Map<String, Integer> all() {
        return stock;
    }

    @PostMapping("/inventory/{sku}/reserve")
    public ResponseEntity<Map<String, Object>> reserve(@PathVariable String sku,
                                                        @RequestParam(defaultValue = "1") int qty)
            throws InterruptedException {
        ThreadLocalRandom rnd = ThreadLocalRandom.current();

        // Simulated latency, with an occasional slow outlier.
        Thread.sleep(rnd.nextInt(100) < 5 ? rnd.nextInt(300, 800) : rnd.nextInt(5, 40));

        // ~3% simulated internal errors so error-rate panels have something to show.
        if (rnd.nextInt(100) < 3) {
            log.error("simulated failure reserving sku={} qty={}", sku, qty);
            return ResponseEntity.internalServerError().body(Map.of("error", "simulated failure"));
        }

        Integer current = stock.get(sku);
        if (current == null) {
            return ResponseEntity.status(404).body(Map.of("error", "unknown sku", "sku", sku));
        }
        if (current < qty) {
            log.warn("out of stock sku={} have={} want={}; restocking", sku, current, qty);
            stock.put(sku, RESTOCK_LEVEL);
            return ResponseEntity.status(409).body(Map.of("error", "out of stock", "sku", sku));
        }

        int remaining = stock.merge(sku, -qty, Integer::sum);
        log.info("reserved sku={} qty={} remaining={}", sku, qty, remaining);
        return ResponseEntity.ok(Map.of("sku", sku, "reserved", qty, "remaining", remaining));
    }
}
