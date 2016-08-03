require 'nokogiri'
require 'open-uri'
require 'pry'

module Jeopardy
  class MissingRoundError < StandardError
  end

  class JArchiveScraper
    J_MULTIPLIER = 100
    DJ_MULTIPLIER = 200
    attr_reader :game

    def initialize
      @games = []
    end

    # Create a new game of jeopardy from a given JArchive source
    # If no source is provided, a random game from a random season is selected
    # Pre: web sources must be fully qualified
    def new_game!(source=nil)
      source = game_list(season_list.sample).sample unless source
      @doc = parse source
      games.push(Game.new(source, rounds))
      @game = games.last
    end

    private
    attr_reader :doc, :games
    SeasonsURL = "http://www.j-archive.com/listseasons.php"
    #TestSeasons = 'test/jeopardy/files/seasons.html'
    #TestGames = 'test/jeopardy/files/episodes.html'

    # Uncaught error: Errno::ENOENT if path is invalid
    def parse source
      Nokogiri::HTML(open(source))
    end

    # Get a list of all seasons of Jeopardy from JArchive or a provided source
    def season_list(source=SeasonsURL)
      seasons_node = parse source
      # 'Real' seasons have names that end in a number (exclude pilot and super jeapordy seasons)
      real_seasons = seasons_node.xpath("//div[@id='content']//a").select { |season| ('0'..'9').include? season.text[-1] }
      real_seasons.map { |season| "http://www.j-archive.com/#{season['href']}" }.reverse 
    end

    # Get a list of all games of Jeopardy from a season, from JArchive or a provided source
    def game_list(source)
      binding.pry
      games_node = parse source
      games_node.xpath("//div[@id='content']//table//a").map { |episode| episode["href"] }.reverse
    end
    
    # Get an array of rounds from the parsed document
    def rounds
      # Rounds are split in to nodes as round 1, round 2, and final round
      r_1_node, r_2_node = doc.xpath("//table[@class='round']")
      final_node = doc.xpath("//table[@class='final_round']").first
      raise MissingRoundError unless r_1_node && r_2_node && final_node
      
      rounds = []
      rounds[0] = Round.new(categories(r_1_node))
      rounds[1] = Round.new(categories(r_2_node))
      rounds[2] = Round.new(final_categories(final_node))
      rounds
    end

    # Get an array of all categories from the provided source node
    def categories(node)
      category_names = node.xpath(".//td[@class='category_name']").map { |cat| cat.text }
      clue_nodes = node.xpath(".//td[@class='clue']")

      6.times.map do |i|
        Category.new(category_names[i], clues(clue_nodes, i))
      end
    end

    # Get an array containing the final round from the provided source
    def final_categories(node)
      category = node.xpath(".//td[@class='category_name']").text
      question = clean_question(node.xpath(".//div//@onmouseover")&.first&.value)
      answer = clean_answer (node.xpath(".//div//@onmouseout")&.first&.value)
      [Category.new(category, [Clue.new(question, answer, 0)])]
    end

    # Get an array of all clues for a given category (represented numerically) from a given source
    def clues(clue_nodes, i)
      (i..29).step(6).map do |j|
        question = clean_question(clue_nodes[j].xpath(".//div//@onmouseover")&.first&.value)
        answer = clean_answer(clue_nodes[j].xpath(".//div//@onmouseout")&.first&.value)
        value = clue_value(clue_nodes[j].xpath(".//@id")&.last&.value)

        # Make q's and a's with bad data 'nil'
        if question.eql?(answer) || (question.eql?("=") && answer.eql?("?"))
          question = answer = nil
        end

        Clue.new(question, answer, value)
      end
    end

    # Get the clean string representation of an answer from a given string source
    def clean_answer(dirty)
      begin
        first = dirty.index(/(?<=stuck', ')./)
        last = dirty.index("')", first)
        dirty[first...last]
      rescue
        # If any step fails, return nil
        nil
      end
    end

    # Get the clean string representation of a question from a given string source
    def clean_question(dirty)
      begin
        first = (dirty.index(/(?<=correct_response\">)./) || dirty.index(/(?<=correct_response\\">)./))
        last = dirty.index("</em>", first)
        dirty[first...last]
      rescue
        # If any step fails, return nil
        nil
      end
    end

    # Calculate the clue value based on the grid co-ordinates
    def clue_value(id_tag)
      return nil if id_tag.nil?
      level = id_tag[-1].to_i
      id_tag.include?("DJ") ? level * DJ_MULTIPLIER : level * J_MULTIPLIER
    end
  end
end
