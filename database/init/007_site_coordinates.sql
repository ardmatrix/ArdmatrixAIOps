UPDATE inventory.sites
SET latitude = CASE site_key
        WHEN 'dc-bengaluru' THEN 12.971600
        WHEN 'customer-dc-01' THEN 12.935200
        WHEN 'dc-delhi' THEN 28.613900
        WHEN 'dc-mumbai' THEN 19.076000
        ELSE latitude
    END,
    longitude = CASE site_key
        WHEN 'dc-bengaluru' THEN 77.594600
        WHEN 'customer-dc-01' THEN 77.624500
        WHEN 'dc-delhi' THEN 77.209000
        WHEN 'dc-mumbai' THEN 72.877700
        ELSE longitude
    END,
    updated_at = now()
WHERE site_key IN ('dc-bengaluru','customer-dc-01','dc-delhi','dc-mumbai');
