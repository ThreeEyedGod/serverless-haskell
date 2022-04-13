{-# LANGUAGE CPP                        #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module AWSLambda.Orphans where

import           Data.Aeson
import           Data.Monoid           ((<>))
import qualified Data.Text             as Text
import           Amazonka.Data.Text (fromText)
import qualified Amazonka.S3        as S3

#if !MIN_VERSION_amazonka_core(1,6,0)
deriving instance FromJSON S3.BucketName
#endif

deriving instance FromJSON S3.ObjectKey

deriving instance FromJSON S3.ObjectVersionId

instance FromJSON S3.ETag where
  parseJSON = withText "ETag" $ either fail return . fromText

instance FromJSON S3.Event where
  parseJSON = withText "Event" $ either fail return . fromText . addS3Prefix
    where
      s3Prefix = "s3:"
      addS3Prefix s =
        if s3Prefix `Text.isPrefixOf` s
          then s
          else s3Prefix <> s
