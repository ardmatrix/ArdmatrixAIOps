FROM grafana/grafana:12.1.1

USER root

COPY branding/ardmatrix-header-logo.png /usr/share/grafana/public/build/static/img/ardmatrix_header.v7.png
COPY branding/ardmatrix-favicon.png /usr/share/grafana/public/build/img/ardmatrix-favicon.v7.png
COPY branding/ardmatrix-apple-touch-icon.png /usr/share/grafana/public/build/img/ardmatrix-apple-touch-icon.v7.png
COPY branding/ardmatrix-official-logo.png /usr/share/grafana/public/img/ardmatrix-official-logo.png
COPY branding/ardmatrix-noc-radial-v1.png /usr/share/grafana/public/img/ardmatrix-noc-radial-v1.png
COPY plugins/ardmatrix-inventory-hub-panel /var/lib/grafana/plugins/ardmatrix-inventory-hub-panel
COPY plugins/ardmatrix-topology-panel /var/lib/grafana/plugins/ardmatrix-topology-panel

RUN sed -i \
      -e 's/grafana_icon\.1e0deb6b\.svg/ardmatrix_header.v7.png/g' \
      -e 's#public/build/img/fav32\.png#public/build/img/ardmatrix-favicon.v7.png#g' \
      -e 's#public/build/img/apple-touch-icon\.png#public/build/img/ardmatrix-apple-touch-icon.v7.png#g' \
      /usr/share/grafana/public/build/app.e299abd209cd47ad567d.js \
      /usr/share/grafana/public/build/swagger.b7fa6c04bd44a97237e6.js \
      /usr/share/grafana/public/build/assets-manifest.json \
    && sed -i \
      -e 's/alt:"Grafana"/alt:"ARDMATRIX AIOps"/g' \
      -e 's/this\.AppTitle="Grafana"/this.AppTitle="ARDMATRIX AIOps"/g' \
      -e 's/this\.LoginTitle="Welcome to Grafana"/this.LoginTitle="Welcome to ARDMATRIX AIOps"/g' \
      -e 's/height:U\.spacing(3),width:U\.spacing(3)/height:U.spacing(3.5),width:U.spacing(22),objectFit:"contain"/g' \
      -e 's/header:(0,a\.css)({alignItems:"center"/header:(0,a.css)({"\& > div:first-child > span":{display:"none"},alignItems:"center"/g' \
      /usr/share/grafana/public/build/9414.e32d7f44873b22e671c7.js \
    && sed -i 's#public/img/fav32\.png#public/build/img/ardmatrix-favicon.v7.png#g' \
      /usr/share/grafana/public/views/error.html \
    && sed -i \
      -e 's#\[\[\.FavIcon\]\]#public/build/img/ardmatrix-favicon.v7.png#g' \
      -e 's#\[\[\.AppleTouchIcon\]\]#public/build/img/ardmatrix-apple-touch-icon.v7.png#g' \
      /usr/share/grafana/public/views/index.html \
    && cp /usr/share/grafana/public/build/app.e299abd209cd47ad567d.js \
      /usr/share/grafana/public/build/app.ardmatrix-v7.js \
    && cp /usr/share/grafana/public/build/9414.e32d7f44873b22e671c7.js \
      /usr/share/grafana/public/build/9414.ardmatrix-v7.js \
    && sed -i \
      -e 's/app\.e299abd209cd47ad567d\.js/app.ardmatrix-v7.js/g' \
      -e 's/9414\.e32d7f44873b22e671c7\.js/9414.ardmatrix-v7.js/g' \
      /usr/share/grafana/public/build/assets-manifest.json

USER grafana
