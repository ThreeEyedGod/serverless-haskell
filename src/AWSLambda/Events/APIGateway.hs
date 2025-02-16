{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE CPP #-}

{-|
Module: AWSLambda.Events.APIGateway
Description: Types for APIGateway Lambda requests and responses

Based on https://github.com/aws/aws-lambda-dotnet/tree/master/Libraries/src/Amazon.Lambda.APIGatewayEvents

To enable processing of API Gateway events, use the @events@ key in
@serverless.yml@ as usual:

> functions:
>   myapifunc:
>     handler: mypackage.mypackage-exe
>     events:
>       - http:
>           path: hello/{name}
>           method: get

Then use 'apiGatewayMain' in the handler to process the requests.
-}
module AWSLambda.Events.APIGateway where

import           Control.Lens            hiding ((.=))
import           Data.Aeson
import           Data.Aeson.Casing       (aesonDrop, camelCase)
import           Data.Aeson.TH           (deriveFromJSON)
-- import           Data.CaseInsensitive (CI (..))
import           Data.Aeson.Embedded
import           Data.Aeson.TextValue
import           Data.Aeson.Types        (Parser)
import           Data.Aeson (Key)
import qualified Data.Aeson.Key as Key
import           Data.ByteString         (ByteString)
import qualified Data.CaseInsensitive    as CI
import           Data.Function           (on)
import           Data.HashMap.Strict     (HashMap)
-- import qualified Data.HashMap.Strict     as HashMap
import qualified Data.Aeson.KeyMap       as KM
import           Data.IP
import qualified Data.Set                as Set
import qualified Data.Text               as Text
import           Data.Text.Encoding      (decodeUtf8, encodeUtf8)
import           GHC.Generics            (Generic)
import           Amazonka.Data.Base64
import           Amazonka.Data.Text
import qualified Network.HTTP.Types      as HTTP
import           Text.Read

import           AWSLambda.Handler       (lambdaMain)

type Method = Text
-- type HeaderName = CI Text
--type HeaderName = Text --- XXX should be CI Text
type HeaderName = Key
type HeaderValue = Text
--type QueryParamName = Text
type QueryParamName = Key
type QueryParamValue = Text
type PathParamName = Text
type PathParamValue = Text
type StageVarName = Text
type StageVarValue = Text

data RequestIdentity = RequestIdentity
  { _riCognitoIdentityPoolId         :: !(Maybe Text)
  , _riAccountId                     :: !(Maybe Text)
  , _riCognitoIdentityId             :: !(Maybe Text)
  , _riCaller                        :: !(Maybe Text)
  , _riApiKey                        :: !(Maybe Text)
  , _riSourceIp                      :: !(Maybe IP)
  , _riCognitoAuthenticationType     :: !(Maybe Text)
  , _riCognitoAuthenticationProvider :: !(Maybe Text)
  , _riUserArn                       :: !(Maybe Text)
  , _riUserAgent                     :: !(Maybe Text)
  , _riUser                          :: !(Maybe Text)
  } deriving (Eq, Show)

readParse :: Read a => String -> Text -> Parser a
readParse msg str =
  case readMaybe (Text.unpack str) of
    Just result -> pure result
    Nothing     -> fail $ "Failed to parse an " ++ msg

instance FromJSON RequestIdentity where
  parseJSON =
    withObject "RequestIdentity" $ \o ->
      RequestIdentity <$> o .:? "cognitoIdentityPoolId" <*> o .:? "accountId" <*>
      o .:? "cognitoIdentityId" <*>
      o .:? "caller" <*>
      o .:? "apiKey" <*>
      (o .:? "sourceIp" >>= traverse (readParse "IP address")) <*>
      o .:? "cognitoAuthenticationType" <*>
      o .:? "cognitoAuthenticationProvider" <*>
      o .:? "userArn" <*>
      o .:? "userAgent" <*>
      o .:? "user"
$(makeLenses ''RequestIdentity)

data Authorizer = Authorizer
  { _aPrincipalId :: !(Maybe Text)
  , _aClaims :: !Object
  , _aContext :: !Object
  } deriving (Eq, Show)
  
instance FromJSON Authorizer where
  parseJSON = withObject "Authorizer" $ \o ->
    Authorizer
      <$> o .:? "principalId"
      <*> o .:? "claims" .!= mempty
      <*> (pure $ KM.delete "principalId" $ KM.delete "claims" o)
     
$(makeLenses ''Authorizer)

data ProxyRequestContext = ProxyRequestContext
  { _prcPath         :: !(Maybe Text)
  , _prcAccountId    :: !Text
  , _prcResourceId   :: !Text
  , _prcStage        :: !Text
  , _prcRequestId    :: !Text
  , _prcIdentity     :: !RequestIdentity
  , _prcResourcePath :: !Text
  , _prcHttpMethod   :: !Text
  , _prcApiId        :: !Text
  , _prcProtocol     :: !Text
  , _prcAuthorizer   :: !(Maybe Authorizer)
  } deriving (Eq, Show)
$(deriveFromJSON (aesonDrop 4 camelCase) ''ProxyRequestContext)
$(makeLenses ''ProxyRequestContext)

data APIGatewayProxyRequest body = APIGatewayProxyRequest
  { _agprqResource              :: !Text
  , _agprqPath                  :: !ByteString
  , _agprqHttpMethod            :: !HTTP.Method
  , _agprqHeaders               :: !HTTP.RequestHeaders
  , _agprqQueryStringParameters :: !HTTP.Query
  -- , _agprqPathParameters        :: !(KM.KeyMap PathParamName PathParamValue)
  -- , _agprqStageVariables        :: !(KM.KeyMap StageVarName StageVarValue)
  , _agprqPathParameters        :: !(KM.KeyMap PathParamValue)
  , _agprqStageVariables        :: !(KM.KeyMap StageVarValue)
  , _agprqRequestContext        :: !ProxyRequestContext
  , _agprqBody                  :: !(Maybe (TextValue body))
  } deriving (Show, Generic)

instance Eq body => Eq (APIGatewayProxyRequest body) where
  (==) =
    (==) `on` \rq ->
      ( _agprqResource rq
      , _agprqPath rq
      , _agprqHttpMethod rq
      , Set.fromList (_agprqHeaders rq) -- header order doesn't matter
      , _agprqQueryStringParameters rq
      , _agprqPathParameters rq
      , _agprqStageVariables rq
      , _agprqRequestContext rq
      , _agprqBody rq)

instance FromText body => FromJSON (APIGatewayProxyRequest body) where
  parseJSON = withObject "APIGatewayProxyRequest" $ \o ->
    APIGatewayProxyRequest
    <$> o .: "resource"
    <*> (encodeUtf8 <$> o .: "path")
    <*> (encodeUtf8 <$> o .: "httpMethod")
    <*> (fmap fromAWSHeaders <$> o .:? "headers") .!= mempty
    <*> (fmap fromAWSQuery <$> o .:? "queryStringParameters") .!= mempty
    <*> o .:? "pathParameters" .!= KM.empty
    <*> o .:? "stageVariables" .!= KM.empty
    <*> o .: "requestContext"
    <*> o .:? "body"
    where
      -- Explicit type signatures so that we don't accidentally tell Aeson
      -- to try to parse the wrong sort of structure
      fromAWSHeaders :: KM.KeyMap HeaderValue -> HTTP.RequestHeaders
      -- fromAWSHeaders :: HashMap HeaderName HeaderValue -> HTTP.RequestHeaders
      fromAWSHeaders = fmap toHeader . KM.toList
        where
          toHeader = bimap (CI.mk . encodeUtf8 . Key.toText) encodeUtf8
--      fromAWSQuery :: HashMap QueryParamName QueryParamValue -> HTTP.Query
      fromAWSQuery :: KM.KeyMap QueryParamValue -> HTTP.Query
      fromAWSQuery = fmap toQueryItem . KM.toList
        where
          toQueryItem = bimap (encodeUtf8 . Key.toText) (\x -> if Text.null x then Nothing else Just . encodeUtf8 $ x)

$(makeLenses ''APIGatewayProxyRequest)

-- | Get the request body, if there is one
requestBody :: Getter (APIGatewayProxyRequest body) (Maybe body)
requestBody = agprqBody . mapping unTextValue

-- | Get the embedded request body, if there is one
requestBodyEmbedded :: Getter (APIGatewayProxyRequest (Embedded v)) (Maybe v)
requestBodyEmbedded = requestBody . mapping unEmbed

-- | Get the binary (decoded Base64) request body, if there is one
requestBodyBinary :: Getter (APIGatewayProxyRequest Base64) (Maybe ByteString)
requestBodyBinary = requestBody . mapping _Base64

data APIGatewayProxyResponse body = APIGatewayProxyResponse
  { _agprsStatusCode :: !Int
  , _agprsHeaders    :: !HTTP.ResponseHeaders
  , _agprsBody       :: !(Maybe (TextValue body))
  } deriving (Show, Generic)

instance (Eq body) => Eq (APIGatewayProxyResponse body) where
  -- header order doesn't matter
  (==) = (==) `on` \r -> (_agprsStatusCode r, Set.fromList (_agprsHeaders r), _agprsBody r)

instance ToText body => ToJSON (APIGatewayProxyResponse body) where
  toJSON APIGatewayProxyResponse {..} =
    object
      [ "statusCode" .= _agprsStatusCode
      , "headers" .= toAWSHeaders _agprsHeaders
      , "body" .= _agprsBody
      ]
    where
      -- toAWSHeaders :: HTTP.ResponseHeaders -> HashMap HeaderName HeaderValue
      toAWSHeaders :: HTTP.ResponseHeaders -> KM.KeyMap HeaderValue
      toAWSHeaders = KM.fromList . fmap (bimap (Key.fromText . decodeUtf8 . CI.original) decodeUtf8)

instance FromText body => FromJSON (APIGatewayProxyResponse body) where
  parseJSON =
    withObject "APIGatewayProxyResponse" $ \o ->
      APIGatewayProxyResponse <$> o .: "statusCode" <*>
      (fromAWSHeaders <$> o .: "headers") <*>
      o .:? "body"
      -- Explicit type signatures so that we don't accidentally tell Aeson
      -- to try to parse the wrong sort of structure
    where
   --   fromAWSHeaders :: HashMap HeaderName HeaderValue -> HTTP.RequestHeaders
      fromAWSHeaders :: KM.KeyMap HeaderValue -> HTTP.RequestHeaders
      fromAWSHeaders = fmap toHeader . KM.toList
        where
          toHeader = bimap (CI.mk . encodeUtf8 . Key.toText) encodeUtf8

$(makeLenses ''APIGatewayProxyResponse)

response :: Int -> APIGatewayProxyResponse body
response statusCode = APIGatewayProxyResponse statusCode mempty Nothing

responseOK :: APIGatewayProxyResponse body
responseOK = response 200

responseNotFound :: APIGatewayProxyResponse body
responseNotFound = response 404

responseBadRequest :: APIGatewayProxyResponse body
responseBadRequest = response 400

responseBody :: Setter' (APIGatewayProxyResponse body) (Maybe body)
responseBody = agprsBody . at () . mapping unTextValue

responseBodyEmbedded :: Setter' (APIGatewayProxyResponse (Embedded body)) (Maybe body)
responseBodyEmbedded = responseBody . mapping unEmbed

responseBodyBinary :: Setter' (APIGatewayProxyResponse Base64) (Maybe ByteString)
responseBodyBinary = responseBody . mapping _Base64

{-| Process incoming events from @serverless-haskell@ using a provided function.

This is a specialisation of 'lambdaMain' for API Gateway.

The handler receives the input event given to the AWS Lambda function, and
its return value is returned from the function.

This is intended to be used as @main@, for example:

> import AWSLambda.Events.APIGateway
> import Control.Lens
> import Data.Aeson
> import Data.Aeson.Embedded
>
> main = apiGatewayMain handler
>
> handler :: APIGatewayProxyRequest (Embedded Value) -> IO (APIGatewayProxyResponse (Embedded [Int]))
> handler request = do
>   putStrLn "This should go to logs"
>   print $ request ^. requestBody
>   pure $ responseOK & responseBodyEmbedded ?~ [1, 2, 3]

The type parameters @reqBody@ and @resBody@ represent the types of request and response body, respectively.
The @FromText@ and @ToText@ contraints are required because these values come from string fields
in the request and response JSON objects.
To get direct access to the body string, use @Text@ as the parameter type.
To treat the body as a stringified embedded JSON value, use @Embedded a@, where @a@ has the
appropriate @FromJSON@ or @ToJSON@ instances.
To treat the body as base 64 encoded binary use @Base64@.
-}
apiGatewayMain
  :: (FromText reqBody, ToText resBody)
  => (APIGatewayProxyRequest reqBody -> IO (APIGatewayProxyResponse resBody)) -- ^ Function to process the event
  -> IO ()
apiGatewayMain = lambdaMain
