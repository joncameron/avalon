# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

class EncodingProfileDocument < ActiveFedora::OmDatastream
  set_terminology do |t|
    t.root(path: 'encodingProfile',
           #:xmlns => 'avalon/encoding',
           namespace_prefix: nil)

    # The quality is a quick way to determine which stream to provide
    # on the fly
    #
    # Expected values are 'low', 'medium', and 'high'
    t.quality(path: 'quality')
    # MIME type is provided to the player so it can serve the right context
    # to the user
    t.mime_type(path: 'mime_type')

    # Both audio and video have a bitrate and codec but video also adds
    # additional information about resolution and framerate since it is
    # visual.
    #
    # An audio profile should always be present but video depends if the
    # content is visual as well.
    t.audio(path: 'audio') do
      t.audio_bitrate(path: 'bitrate')
      t.audio_codec(path: 'codec')
    end

    t.video(path: 'video') do
      t.video_bitrate(path: 'bitrate')
      t.video_codec(path: 'codec')

      t.resolution do
        t.video_width(path: 'width')
        t.video_height(path: 'height')
      end
      t.frame_rate(path: 'framerate')
    end
  end

  def self.xml_template
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.encodingProfile do
        xml.quality
        xml.mime_type

        xml.audio do
          xml.bitrate
          xml.codec
        end
      end
    end
    builder.doc
  end

  def prefix
    ''
  end
end
