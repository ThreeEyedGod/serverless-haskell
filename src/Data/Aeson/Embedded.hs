{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TemplateHaskell            #-}

{-|
Module: Data.Aeson.Embedded
Description: Type for a JSON value embedded within a JSON string value
-}
module Data.Aeson.Embedded where

import           Control.Lens.TH
import           Data.Aeson
import qualified Data.ByteString.Lazy as LBS
import           Data.Text.Encoding    (decodeUtf8, encodeUtf8)
import           Amazonka.Data.Text (FromText (..), ToText (..), fromText)
import qualified Data.Attoparsec.Text as AText
import           Data.Text                         (Text)


-- | Type for a JSON value embedded within a JSON string value
newtype Embedded a = Embedded { _unEmbed :: a } deriving (Eq, Show)

instance FromJSON a =>
         FromText (Embedded a) where
--  parser =
    fromText = 
         fmap Embedded . eitherDecodeStrict . encodeUtf8
      -- fmap Embedded . either fail pure . eitherDecodeStrict . encodeUtf8 =<< takeText
       
instance FromJSON a =>
         FromJSON (Embedded a) where
  parseJSON v = either fail pure . fromText =<< parseJSON v
  

instance ToJSON a => ToText (Embedded a) where
  toText = decodeUtf8 . LBS.toStrict . encode . _unEmbed

instance ToJSON a => ToJSON (Embedded a) where
  toJSON = toJSON . toText
  toEncoding = toEncoding . toText

$(makeLenses ''Embedded)
