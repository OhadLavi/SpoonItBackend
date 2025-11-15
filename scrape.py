from base64 import b64decode

import requests

api_response = requests.post(
    "https://api.zyte.com/v1/extract",
    auth=("5a94c272bd484e6493cab59a83d56672", ""),
    json={
        "url": "https://kerenagam.co.il/%d7%a8%d7%95%d7%9c%d7%93%d7%aa-%d7%98%d7%99%d7%a8%d7%9e%d7%99%d7%a1%d7%95-%d7%99%d7%a4%d7%99%d7%a4%d7%99%d7%99%d7%94/",
        "pageContent": True,
        "pageContentOptions": {"extractFrom":"httpResponseBody"},
        "followRedirect": True,
    },
)
pageContent = api_response.json()["pageContent"]
print(pageContent)