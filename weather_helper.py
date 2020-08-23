import json
import sqlite3
from math import exp, log
import sys
import requests
from metar import Metar
from pytz import utc
from dateutil.parser import parse
from datetime import datetime
from functools import lru_cache

class Weather(object):
    def __init__(self):
        self.session = requests.Session()
        self.session.headers['Accept'] = 'application/geo+json,application/json,*/*'
        self._db_connection = None
        self.MESONET_URL = 'http://mesonet.agron.iastate.edu/json/current.py?station={station}&network={state}_ASOS'
        self.METAR_URL = 'https://tgftp.nws.noaa.gov/data/observations/metar/stations/{station}.TXT'

    @staticmethod
    def fail(message=None):
        if message:
            print(f'wx: {message}')
        else:
            print('wx: invalid location')
        # sys.exit()

    @staticmethod
    def dict_factory(cursor, row):
        d = {}
        for idx, col in enumerate(cursor.description):
            d[col[0]] = row[idx]
        return d

    def get_database_connection(self):
        if self._db_connection:
            return self._db_connection
        self._db_connection = sqlite3.connect('/afs/dsrw.org/public/databases/wx.db')
        self._db_connection.row_factory = self.dict_factory
        return self._db_connection
    
    def query_database(self, query, params=None, debug=False):
        conn = self.get_database_connection()
        if not params:
            params = []
        elif not isinstance(params, list):
            params = [params]
        if debug:
            print(f'DEBUG query:  {query}')
            print(f'DEBUG params: {str(params)}')
        result = conn.execute(query, params)
        return result.fetchall()

    @staticmethod
    def f_to_c(f):
        return (f - 32) * 5 / 9
    
    @staticmethod
    def c_to_f(c):
        return 32 + (c * 1.8)

    def temperature(self, temp):
        '''format an integer as F temp'''
        temp = int(temp)
        return f'{temp} F ({self.f_to_c(temp)} C)'
    
    @staticmethod
    def speed(speed=None):
        '''format an integer as MPH speed'''
        if not speed:
            return None
        return f'{speed} MPH'

    @staticmethod
    def pressure(pressure=None):
        '''format an integer as millibars of pressure'''
        if not pressure:
            return None
        return f'{pressure} mb'

    @staticmethod
    def direction(deg):
        '''format an integer as a direction'''
        if not isinstance(deg, int):
            return 'unknown'
        elif deg >= 338 or deg < 23:
            return 'north'
        elif deg < 68:
            return 'northeast'
        elif deg < 113:
            return 'east'
        elif deg < 158:
            return 'southeast'
        elif deg < 203:
            return 'south'
        elif deg < 248:
            return 'southwest'
        elif deg < 293:
            return 'west'
        else:
            return 'northwest'

    @staticmethod
    def wind_chill(temp, windspeed):
        '''given temp in F and windspeed in MPH, return windchill in F
           https://www.weather.gov/epz/wxcalc_windchill
           https://www.weather.gov/media/epz/wxcalc/windChill.pdf
        '''
        if temp > 50 or windspeed < 3:
            return temp
        return 35.74 + (0.6215 * temp) \
               - (35.75 * windspeed ** 0.16) \
               + (0.4275 * temp * windspeed ** 0.16)
    
    @staticmethod
    def heat_index(temp, humidity):
        '''given temp in F and humidity in %, return heat index in F
           https://www.weather.gov/epz/wxcalc_heatindex
           https://www.weather.gov/media/epz/wxcalc/heatIndex.pdf
        '''
        if temp < 80:
            return temp
        return -42.379 + (2.04901523 * temp) + (10.14333127 * humidity) \
               - (0.22475541 * temp * humidity) \
               - (6.83783 * 10**-3 * temp**2) \
               - (5.481717 * 10**-2 * humidity**2) \
               + (1.22874 * 10**-3 * temp**2 * humidity) \
               + (8.5282 * 10**-4 * temp * humidity**2) \
               - (1.99 * 10**-6 * temp**2 * humidity**2)
    
    def dew_point(self, temp, humidity, pressure):
        '''given temp in F, humidity in % and pressure in mb, return dew_point in f
           https://www.weather.gov/epz/wxcalc_rh
           https://www.weather.gov/media/epz/wxcalc/wetBulbTdFromRh.pdf
        '''
        temp_c = self.f_to_c(temp)
        sat_vap_press = 6.112 * exp(17.67 * temp_c / (temp_c + 243.5))
        act_vap_press = sat_vap_press * (humidity / 100)
        return self.c_to_f(
            (243.5 * log(act_vap_press/6.112)) / (17.67 - log(act_vap_press/6.112))
        )

    @staticmethod
    def e_sub_x(x):
        '''dark magic for def humidity()'''
        return 6.112 * exp((17.67 * x) / (x + 243.5))

    def humidity(self, temp, dwp):
        '''given temp in F and dewpoint in F, return humidity in pct
           https://www.weather.gov/epz/wxcalc_dewpoint
           https://www.weather.gov/media/epz/wxcalc/rhWetBulbFromTd.pdf
        '''
        temp_c = self.f_to_c(temp)
        dwp_c = self.f_to_c(dwp)
        return 100 * self.e_sub_x(dwp_c) / self.e_sub_x(temp_c)
    
    def check_metar_station(self, station, state=''):
        metar_data = self.query_database(
            'select * from stations where station=?',
            station
        )
        for metar_row in metar_data:
            if metar_row.get('metar'):
                return metar_row.get('metar')
        station_ok = -1
        metar_request = requests.head(self.METAR_URL.format(station=station.upper()))
        if metar_request.status_code == 200:
            update_datetime = parse(metar_request.headers.get('Last-Modified', "1 January 1970"))
            if (datetime.now(utc) - update_datetime).days < 5: # current enough!
                station_ok = 1
        self.query_database(
            'UPDATE stations set metar=? where station=?',
            [station_ok, station], debug=False
        )
        return station_ok


    def get_metar_data(self, station):
        metar_data = requests.get(self.METAR_URL.format(station=station.upper()))
        if metar_data.status_code != 200:
            self.fail(f"couldn't retrieve METAR data for {station}")
        for line in metar_data.text.split('\n'):
            if line.startswith(station.upper()):
                return Metar.Metar(line)
        return None


    def get_mesonet_metar_data(self, station, state):
        wx_data = self.get_mesonet_data(station, state)
        return Metar.Metar(wx_data.get('raw'))


    def check_mesonet_station(self, station, state):
        station_og = station
        mesonet_data = self.query_database(
            'select * from stations where station=?',
            station_og
        )
        for mesonet_row in mesonet_data:
            if mesonet_row.get('mesonet'):
                return mesonet_row.get('mesonet')
        station_ok = -1
        station = station.upper()
        state = state.upper()
        if station.startswith('K') and len(station) == 4:
            station = station[2:]
        url = self.MESONET_URL.format(station, state)
        response = self.session.get(url)
        if response.status_code != 200:
            self.fail("didn't get data from mesonet")
        try:
            mesonet_json = response.json()
            if 'last_ob' in mesonet_json:
                station_ok = 1
        except Exception:
            pass
        self.query_database(
            'UPDATE stations set mesonet=? where station=?',
            [station_ok, station_og]
        )
        return station_ok
        
    def get_mesonet_data(self, station, state):
        station = station.upper()
        state = state.upper()
        if station.startswith('K') and len(station) == 4:
            station = station[1:]
        url = self.MESONET_URL.format(station=station, state=state)
        response = self.session.get(url)
        try:
            return response.json().get('last_ob')
        except Exception:
            pass
        return None


    def get_local_station(self, lat, lng):
        discards = []
        found = False
        i = 1
        # metar != -1 and
        base_q = 'select * from stations where  lat < ? and lat > ? and long < ? and long > ?'
        while i < 100 and not found:
            q = base_q
            distance = i * .05
            params = [
                lat + distance,
                lat - distance,
                lng + distance,
                lng - distance      
            ]
            if discards:
                q += (' and station not in ('
                      f"{('?, ' * len(discards)).rstrip(', ')}"
                      ')'
                     )
                params += discards
            for station in self.query_database(q, params):
                # print(station)
                if station.get('metar') == 1 \
                   or self.check_metar_station(station.get('station')) == 1:
                    found = True
                    break
            i += 1
        if found:
            return (
                station.get('station'),
                station.get('station_name'),
                station.get('state')
            )
        self.fail("I could not find a station.")
        return None

    def get_zone(self, lat, lng, full_url=False):
        resp = self.session.get(f'https://api.weather.gov/points/{lat},{lng}')
        try:
            result = resp.json().get('properties', {}).get('forecastZone')
            timezone = resp.json().get('properties', {}).get('timeZone')
            if not result:
                raise Exception('bad data')
            if full_url:
                return result, timezone
            else:
                return result.split('/').pop(), timezone
        except Exception:
            pass
        self.fail("can't get a valid zone")
    
    def get_station(self, lat, lng):
        forecast_url = self.get_zone(lat, lng, full_url=True)
        resp = self.session.get(f'{forecast_url}/stations')
        for station in resp.json().get('features', []):
            # print(station)
            try:
                station_data = self.session.get(station.get('id')).json()
            except Exception:
                self.fail(f"couldn't retrieve data from {station.get('id')}.")
            station_id = station_data.get('properties', {}).get('stationIdentifier')
            county = station_data.get('properties', {}).get('county').split('/').pop()
            state = county[0:2]
            if self.get_mesonet_data(station_id, state):
                (city, _) = station_data.get('properties', {}).get('name').split(",", 2)
                return (
                    station_id,
                    city,
                    state
                )
        self.fail("could not match a station with data")

    @lru_cache(maxsize=256)
    def geocode(self, location):
        cache_data = self.query_database(
            ('select zone, lat, long, station, station_name, state, '
             'timezone from geocode where location like ?'
            ),
            location
        )
        if cache_data:
            return list(cache_data[0].values())
        lat = 0
        lng = 0
        if len(location) == 3:
            location = f'k{location}'
        if len(location) == 4:
            location = location.upper()
            try:
                station_lookup = self.session.get(
                    f'https://api.weather.gov/stations/{location}'
                ).json()
                if station_lookup.get('geometry', {}).get('coordinates'):
                    (lng, lat) = station_lookup.get('geometry', {}).get('coordinates')
            except:
                pass
        if not lng:
            mapquest_key = 'ZZlkNJlXCoBU4gZdnla5oikZKYxAYcqK'
            try:
                mapquest_results = self.session.get(
                    f"https://www.mapquestapi.com/geocoding/v1/address?key={mapquest_key}&informat=kvp&outFormat=json&location={location}"
                ).json()
            except Exception:
                self.fail('could not get data from mapquest')
            for result in mapquest_results.get('results', []):
                # print(result)
                for mq_location in result.get('locations', []):
                    if 'latLng' in mq_location:
                        lat = mq_location.get('latLng').get('lat')
                        lng = mq_location.get('latLng').get('lng')
                        break
        if not lng:
            self.fail(f'could not geocode {location}')
        # print(f'lat: {lat} // lng: {lng}')
        (station_id, station_name, state) = self.get_local_station(lat, lng)
        (zone_id, timezone) = self.get_zone(lat, lng)
        self.query_database(
            ('insert into geocode '
             '    (location, lat, long, station, station_name, state, zone, timezone)'
             '    VALUES (?,?,?,?,?,?,?,?)'),
             [location, lat, lng, station_id, station_name, state, zone_id, timezone]
        )
        return [
            zone_id, lat, lng, station_id, station_name, state, timezone
        ]

    def alerts(self, location):
        (zone_id, lat, lng, station_id, station_name, state, timezone) = self.geocode(location)
        now = datetime.now(utc)
        alerts = set()
        response = self.session.get(f'https://api.weather.gov/alerts/active?point={lat},{lng}')
        if response.status_code != 200:
            self.fail('could not get alerts')
        for alert in response.json().get('features', []):
            event = alert.get('properties', {}).get('event')
            starts = parse(alert.get('properties', {}).get('onset'))
            ends = parse(alert.get('properties', {}).get('ends'))
            message = f'{event} '
            if now < starts:
                message += 'from '
                if now.date() != starts.date():
                    message += f'{starts.month}/{starts.day} at '
                message += f'{starts.hour:02d}:{starts.minute:02d} '
            if now < ends:
                message += 'until '
                if now.date() != ends.date():
                    message += f'{ends.month}/{ends.day} at '
                message += f'{ends.hour:02d}:{ends.minute:02d}'
            alerts.add(message)
        return list(alerts)

        

        


