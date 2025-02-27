CREATE OR REPLACE FUNCTION vocabulary_pack.py_ohdsi_wiki(doc_id text, doc_body text, ohdsi_login text, ohdsi_password text)
RETURNS text AS
$BODY$
  #A small script for publishing any text on the OHDSI's Wiki
  #Returns 'OK' if success
  import re, requests
  s = requests.session()

  #log in
  data={
      'u': ohdsi_login,
      'p': ohdsi_password
  }

  ohdsi_post=s.post('https://www.ohdsi.org/web/wiki/doku.php?do=login', data=data, timeout=30, verify=False).text

  #get the new security token. if error return full HTML-page
  sectok=re.findall('<input type="hidden" name="sectok" value="(.*?)" />',ohdsi_post)[0]
  if sectok=='':
      return ohdsi_post
    
  #send the WiKi data
  data = {
      'id': doc_id,
      'sectok': sectok,
      'target' : 'section',
      'wikitext': doc_body,
      'do[save]' : ''
  }

  ohdsi_post=s.post('https://www.ohdsi.org/web/wiki/doku.php?id=' + doc_id, data=data, timeout=30, verify=False)
    
  return 'OK'
$BODY$
LANGUAGE 'plpython3u' STRICT;