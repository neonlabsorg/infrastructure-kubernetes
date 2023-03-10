    helm upgrade --install prometheus prometheus-community/prometheus \
      -f monitoring/prometheus/values.yaml \
      --namespace=neon-proxy \
      --history-max 3 \
      --set server.persistentVolume.storageClass="gp2" \
      --set server.persistentVolume.size="500Gi" \
      --set alertmanager.persistence.storageClass="gp2" \
      --set alertmanager.persistence.size="500Gi" \
      --set-file extraScrapeConfigs=monitoring/prometheus/extraScrapeConfigs.yaml 1>/dev/null
