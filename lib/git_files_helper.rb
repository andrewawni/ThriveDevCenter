# frozen_string_literal: true

require 'fileutils'
require 'uri'
require 'open3'

LOCAL_GIT_TARGET_FOLDER ||= 'tmp/git_repos'

# Helper for cloning and inspecting the files of a git repo
module GitFilesHelper
  # The main method
  def self.update_files(lfs_project)
    if lfs_project.clone_url.blank?
      Rails.logger.warn 'Lfs project has blank clone url, skipping it'
      return
    end

    git_checkout lfs_project

    # Skip update if still the same commit
    commit = current_commit lfs_project
    if commit == lfs_project.file_tree_commit
      Rails.logger.info "Lfs project (#{lfs_project.name}) has up" \
                        ' to date files for current commit'
      return
    end

    add_and_update_file_objects lfs_project
    delete_non_existant_objects lfs_project

    lfs_project.file_tree_commit = commit
    lfs_project.file_tree_updated = Time.now
    lfs_project.save!
  end

  def self.delete_all_file_objects(lfs_project)
    # Clear the commit to make the rebuild work
    lfs_project.file_tree_commit = nil
    lfs_project.save!

    ProjectGitFile.where(lfs_project_id: lfs_project.id).destroy_all
  end

  def self.add_and_update_file_objects(lfs_project)
    folders = {}

    loop_local_files(lfs_project) { |file, inside_path|
      dir = process_folder_path(File.dirname(inside_path))

      is_normal = !File.directory?(file)

      if folders.include? dir
        folders[dir][:item_count] += 1
      else
        folders[dir] = {
          item_count: 1,
          recursive_normal_count: 0
        }
      end

      if is_normal
        folders[dir][:recursive_normal_count] += 1
        get_all_parent_folders(dir).each { |parent|
          if folders.include? parent
            folders[parent][:recursive_normal_count] += 1
          else
            folders[parent] = {
              item_count: 0,
              recursive_normal_count: 0
            }
          end
        }
      end

      # Git can leave behind empty folders, that's why we need complex handling for folders
      # that don't contain files as child entries (even recursively).
      # This is because git can leave behind empty folders
      next unless is_normal

      filename = File.basename inside_path

      oid, size = detect_lfs_file file

      size = File.size file if oid.nil?

      existing = ProjectGitFile.find_by lfs_project: lfs_project, name: filename,
                                        path: dir

      if !existing
        ProjectGitFile.create! lfs_project: lfs_project, name: filename, path: dir,
                               lfs_oid: oid, size: size, ftype: 'file'
      else
        existing.lfs_oid = oid
        existing.size = size
        existing.ftype = 'file'
        existing.save! if existing.changed?
      end
    }

    # Create folders
    folders.each { |folder, data|
      next unless data[:recursive_normal_count]

      dir = process_folder_path(File.dirname(folder))
      filename = File.basename folder

      existing = ProjectGitFile.find_by lfs_project: lfs_project, name: filename,
                                        path: dir

      if !existing
        ProjectGitFile.create! lfs_project: lfs_project, name: filename, path: dir,
                               lfs_oid: nil, size: data[:item_count], ftype: 'folder'
      else
        existing.lfs_oid = nil
        existing.size = data[:item_count]
        existing.ftype = 'folder'
        existing.save! if existing.changed?
      end
    }
  end

  def self.delete_non_existant_objects(lfs_project)
    local_base = folder lfs_project

    ProjectGitFile.where(lfs_project_id: lfs_project.id, ftype: 'file').find_each { |file|
      local_file = File.join(local_base, file.path, file.name)

      file.destroy unless File.exist? local_file
    }

    # TODO: delete empty folders
  end

  def self.process_folder_path(folder)
    if folder.blank? || folder == '.'
      '/'
    elsif folder[0] != '/'
      '/' + folder
    else
      folder
    end
  end

  def self.get_all_parent_folders(folder)
    parts = folder.split '/'

    (1..parts.size).map { |n|
      result = parts.take(n).join('/')

      if result.blank? || result[0] != '/'
        '/' + result
      else
        result
      end
    }
  end

  def self.detect_lfs_file(file)
    File.open(file) { |f|
      data = f.read(4048)

      size = nil
      oid = nil

      if %r{.*version https://git-lfs\.github\.com.*}i.match?(data)
        # Lfs file
        data.each_line { |line|
          if (match = line.match(/oid sha256:(\w+)/i))
            oid = match.captures[0]
            next
          end
          if (match = line.match(/size (\d+)/i))
            size = match.captures[0].to_i
            next
          end
        }
      end

      return [oid, size]
    }

    [nil, nil]
  end

  def self.loop_local_files(lfs_project)
    search_start = folder(lfs_project)
    prefix = File.join search_start, ''

    Dir.glob(File.join(search_start, '**/*')) { |f|
      yield [f, f.sub(prefix, '')]
    }
  end

  def self.folder(lfs_project)
    File.join LOCAL_GIT_TARGET_FOLDER, File.basename(URI.parse(lfs_project.clone_url).path)
  rescue URI::InvalidURIError
    File.join LOCAL_GIT_TARGET_FOLDER, File.basename(lfs_project.clone_url)
  end

  def self.git_checkout(lfs_project)
    FileUtils.mkdir_p LOCAL_GIT_TARGET_FOLDER
    git_clone lfs_project unless File.exist? folder(lfs_project)

    # TODO: might be nice to have error reporting for these
    Open3.capture2 env, 'git checkout master', chdir: folder(lfs_project)
    Open3.capture2 env, 'git pull', chdir: folder(lfs_project)
  end

  def self.git_clone(lfs_project)
    system env, 'git', 'clone', lfs_project.clone_url, folder(lfs_project)

    if $CHILD_STATUS.exitstatus.nil? || !$CHILD_STATUS.exitstatus.zero?
      Rails.logger.error 'Git clone failed'
      raise 'Cloning git repo failed'
    end
  end

  def self.env
    { 'GIT_LFS_SKIP_SMUDGE' => '1' }
  end

  # Returns the current git commit
  def self.current_commit(lfs_project)
    output, status = Open3.capture2 'git rev-parse HEAD', chdir: folder(lfs_project)

    throw 'Git rev-parse failed' if status != 0

    output.strip
  end
end
