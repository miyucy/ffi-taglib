# -*- coding: utf-8 -*-
require 'rubygems'
require 'ffi'

module TagLib
  module Native
    module Binding
      extend FFI::Library
      ffi_lib 'tag_c'

      attach_function :file_new,              :taglib_file_new,                   [:string],           :pointer
      attach_function :file_new_type,         :taglib_file_new_type,              [:string, :int],     :pointer
      attach_function :file_free,             :taglib_file_free,                  [:pointer],          :void
      attach_function :file_is_valid,         :taglib_file_is_valid,              [:pointer],          :int
      attach_function :file_tag,              :taglib_file_tag,                   [:pointer],          :pointer
      attach_function :file_properties,       :taglib_file_audioproperties,       [:pointer],          :pointer
      attach_function :file_save,             :taglib_file_save,                  [:pointer],          :int
      attach_function :tag_title,             :taglib_tag_title,                  [:pointer],          :string
      attach_function :tag_artist,            :taglib_tag_artist,                 [:pointer],          :string
      attach_function :tag_album,             :taglib_tag_album,                  [:pointer],          :string
      attach_function :tag_comment,           :taglib_tag_comment,                [:pointer],          :string
      attach_function :tag_genre,             :taglib_tag_genre,                  [:pointer],          :string
      attach_function :tag_year,              :taglib_tag_year,                   [:pointer],          :int
      attach_function :tag_track,             :taglib_tag_track,                  [:pointer],          :int
      attach_function :properties_length,     :taglib_audioproperties_length,     [:pointer],          :int
      attach_function :properties_bitrate,    :taglib_audioproperties_bitrate,    [:pointer],          :int
      attach_function :properties_samplerate, :taglib_audioproperties_samplerate, [:pointer],          :int
      attach_function :properties_channels,   :taglib_audioproperties_channels,   [:pointer],          :int
      attach_function :tag_set_title,         :taglib_tag_set_title,              [:pointer, :string], :void
      attach_function :tag_set_artist,        :taglib_tag_set_artist,             [:pointer, :string], :void
      attach_function :tag_set_album,         :taglib_tag_set_album,              [:pointer, :string], :void
      attach_function :tag_set_comment,       :taglib_tag_set_comment,            [:pointer, :string], :void
      attach_function :tag_set_genre,         :taglib_tag_set_genre,              [:pointer, :string], :void
      attach_function :tag_set_year,          :taglib_tag_set_year,               [:pointer, :int],    :void
      attach_function :tag_set_track,         :taglib_tag_set_track,              [:pointer, :int],    :void

      attach_function :taglib_id3v2_set_default_text_encoding, [:int], :void
    end

    class File < FFI::Struct
      layout :dummy, :int
    end

    class Tag < FFI::Struct
      layout :dummy, :int
    end

    class Properties < FFI::Struct
      layout :dummy, :int
    end
  end

  class File
    MPEG      = 0
    OggVorbis = 1
    FLAC      = 2
    MPC       = 3
    OggFlac   = 4
    WavPack   = 5
    Speex     = 6
    TrueAudio = 7

    def self.open path, type=nil, autosave=false
      file = File.new(path, type)
      return file unless block_given?

      begin
        yield(file)
      rescue
        raise
      else
        file.save if autosave and file.need_save?
      ensure
        file.close
      end
    end

    def self.valid? path, type=nil
      File.open(path, type).valid?
    end

    @@target = []
    def self.terminator
      @@target.each{ |ptr| Native::Binding.file_free ptr }
    end
    at_exit{ TagLib::File.terminator }

    def initialize path, type=nil
      path = ::File.expand_path(path)
      raise ArgumentError unless test(?e, path)

      @ptr = if type
              raise ArgumentError unless TypeRange.include? type
              Native::Binding.file_new_type path, type
            else
              Native::Binding.file_new path
            end
      @file = Native::File.new @ptr
      @path = path
      @need_save = false
      @memo = {}
      @closed = false
      @@target << @ptr
    end

    def valid?
      raise IOError if @closed
      Native::Binding.file_is_valid(@file) == 1
    end

    def save
      raise IOError if @closed
      raise IOError unless Native::Binding.file_save(@file) == 1
      @need_save = false
      @memo.clear
    end

    def need_save?
      @need_save
    end

    def close
      raise IOError if @closed
      Native::Binding.file_free @ptr
      @closed = true
      @need_save = false
      @file = @memo = nil
      @@target.delete @ptr
    end

    def method_missing(method_name, *args)
      attributes = {
        :title      => {:acc => :rw, :cast => :to_s,},
        :artist     => {:acc => :rw, :cast => :to_s,},
        :album      => {:acc => :rw, :cast => :to_s,},
        :comment    => {:acc => :rw, :cast => :to_s,},
        :genre      => {:acc => :rw, :cast => :to_s,},
        :year       => {:acc => :rw, :cast => :to_i,},
        :track      => {:acc => :rw, :cast => :to_i,},
        :length     => {:acc => :ro, :cast => :to_i,},
        :bitrate    => {:acc => :ro, :cast => :to_i,},
        :samplerate => {:acc => :ro, :cast => :to_i,},
        :channels   => {:acc => :ro, :cast => :to_i,},
      }

      puts method_name
      puts %<(#{attributes.map{ |k,v| "#{k}" if v[:acc] == :rw }.compact.join("|")})=\\Z>
      if method_name.to_s =~ Regexp.new(%<(#{attributes.map{ |k,v| "#{k}" if v[:acc] == :rw }.compact.join("|")})=\\Z>)
        raise IOError if @closed
        # setter
        attribute     = $1.to_sym
        native_method = "tag_set_#{attribute}".to_sym
        value         = args.first.method(attributes[attribute][:cast]).call

        @memo[attribute] ||= instance_eval("self.#{attribute}").method(attributes[attribute][:cast]).call

        if @memo[attribute] != value
          @memo[attribute] = value
          Native::Binding.method(native_method).call(tag, value)
          @need_save = true
        end

        return value
      else
        # getter
        attribute = method_name
        if attributes[attribute][:acc] == :ro
          native_method = "properties_#{attribute}".to_sym
          argument      = properties
        else
          native_method = "tag_#{attribute}".to_sym
          argument      = tag
        end
        if Native::Binding.respond_to? native_method
          raise IOError if @closed
          return @memo[attribute] ||= Native::Binding.method(native_method).call(argument)
        end
      end
      super
    end

    private
    TypeRange = MPEG..TrueAudio

    def tag
      @tag ||= Native::Tag.new(Native::Binding.file_tag @file)
    end

    def properties
      @properties ||= Native::Properties.new(Native::Binding.file_properties @file)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'pp'

  f = TagLib::File.open(File.expand_path("~/tmp/01 Title.mp3"), TagLib::File::MPEG)
  puts f.title
  puts f.artist
  puts f.album
  puts f.comment
  puts f.genre
  puts f.year
  puts f.track
  puts f.length
  puts f.bitrate
  puts f.samplerate
  puts f.channels
  pp f

  puts

  TagLib::File.open(File.expand_path("~/tmp/01 Title.mp3")){ |f|
    puts f.track = 9
    puts f.album = 3
    puts f.need_save?
    pp f
    puts f.title
    puts f.artist
    pp f
    # f.save
  }
end
