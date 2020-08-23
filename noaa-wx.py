import cgi
from weather_helper import Weather
from datetime import timezone
from dateutil import tz
from metar import Metar

print ("Content-Type: text/html\n\n")

w = Weather()
arguments = cgi.FieldStorage()
print(arguments)

if 'location' not in arguments:
    print('Missing location')
    sys.exit()

location = arguments.get('location')
(zone, lat, long, station, placename, state, station_tz) = w.geocode(location)

metar = w.get_metar_data(station)
obs_time = metar.time.replace(tzinfo=timezone.utc).astimezone(tz=tz.gettz(station_tz))
print(f'wx: {placename}, {state} at {obs_time.strftime("%H:%M")} L')
for alert in w.alerts(location):
    print(f"4 ** {alert}")

if metar.weather:
    conditions = metar.weather
else:
    conditions = Metar.SKY_COVER.get(metar.sky[-1][0], "WEATHERY")
print(f' - Currently {conditions} and {metar.temp.string("F")} ({metar.temp.string("C")})')
temp = metar.temp.value('F')
humidity = w.humidity(temp, metar.dewpt.value('F'))
windchill = w.wind_chill(temp, metar.wind_speed.value('MPH'))
heatindex = w.heat_index(temp, humidity)